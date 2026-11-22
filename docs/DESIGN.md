# Madal v0 design

Madal publishes HTML and Markdown artifacts from any coding agent to a link. The CLI encrypts
everything before upload. The server stores ciphertext and never sees a key. This doc pins the
parts that are expensive to change later: the envelope format, the URL shape, the two origins and
the data model.

## Pieces

- `madal` is a single Go binary. It does all crypto locally, talks to the API, and keeps the API token
  in the OS keychain.
- `madald` is the server, one Go binary that runs in two modes from one image. `MODE=app` serves
  the API, the viewer shell and the sign-in pages. `MODE=content` serves only the artifact frame
  and public artifact bodies.
- `skill/SKILL.md` teaches an agent when and how to call the CLI.

## Tiers

**Private tier** (the default for a signed-in publish with sharing keys on the machine). The link
carries no key. The artifact key is wrapped to the owner's account key, and to anyone shared with
by name, so it opens wherever the owner is signed in and unlocked. A forwarded link opens nothing.

**Link tier** (`--link`, or any publish while signed out). The key lives in the URL fragment,
which browsers never send to a server. Anyone with the full link can read it. Anyone without the
fragment gets ciphertext. An optional password adds a second factor: the link alone is not
enough. When the publisher is signed in, the owner also gets a grant, so a link without its
fragment still opens for them, and their other machines can open and update it.
Its owner (or an org admin who manages it) can reset the link: the fragment then reads
`<key>.<token>`, where the token is random and checked by the server on the blob, comment and
history routes; the page record still answers by id, without the sealed title. Clients send it in a `Madal-Link-Token` header, never in a URL, so it stays out of access
logs; with signed downloads the blob route then answers the storage link as JSON instead of
redirecting, so the header never reaches storage. A reset cuts off every copy of the old link at
once without changing the key. Links from before a page's first reset carry no token and keep
working until then. When a page changes owner (an admin takes it over, or it passes to the org), the
server cuts its link the same way, with the hash of a token nobody holds, since the previous owner
keeps the key and the link. It can't seal a token with the page key, so it tells the page's
managers `link_cut`, and the client that makes the page a link page again resets the link.

**Public tier.** Plaintext, for signed-in accounts only. The server stores the HTML and serves
Open Graph tags so links unfurl in Slack and on social sites, with a 1200x630 card image drawn
server-side from the title, description and (when shown) owner name. The card URL carries a hash
of those, so an edit gets a new URL and crawlers don't keep the old card. Public means public: no
encryption claim is made for this tier.

**Link previews of encrypted pages.** `/a/<id>` is one static file. Every link and private page,
and every id that doesn't exist, gets the same bytes and the same card ("Encrypted page on
Madal"), as Proton Drive and Bitwarden Send do. Nothing derived from the page goes into that
HTML, not its owner, expiry or title, so a crawler can't tell a real id from a made-up one.
Crawler fetches of the HTML or the card never count toward a page's open limit; only the blob
API counts opens.

## Envelope format (v1, v2)

```
content key  K   = 32 random bytes (CSPRNG)
link             = https://<app>/a/<id>#<base64url(K)>        (no padding)

no password      EK = K
with password    S  = PBKDF2-SHA256(password, salt16, 600000 iterations, 32 bytes)
                 EK = HKDF-SHA256(ikm = K, salt = S, info = "madal/v1/content", 32 bytes)

AAD              = "madal/v1/" + id + "/" + version
blob             = "MDL1" || nonce(12) || AES-256-GCM(EK, nonce, plaintext, AAD)
plaintext        = JSON {"title", "type": "html"|"markdown", "html"}

v2 (what clients publish now; v1 blobs still open):
AAD2             = "madal/v2/" + id + "/" + version
blob             = "MDL2" || nonce(12) || AES-256-GCM(EK, nonce, inner, AAD2)
inner            = flag(1) || len(4, big-endian) || payload || zeros, to padded(5 + len)
flag             = 0: payload is the JSON above; 1: payload is that JSON gzipped
padded(n)        = 4096 if n <= 4096, else Padmé(n)
```

Decisions and why:

- **Password is HKDF over the fragment key, not a replacement for it.** A password-only key would
  let anyone holding the ciphertext brute-force the password offline. Mixing it with a 256-bit
  random key means a server breach yields nothing, and a leaked link still needs the password.
- **PBKDF2, not Argon2.** The browser decrypts with WebCrypto, which has PBKDF2 and no Argon2.
  600,000 iterations follows the OWASP 2023 figure for PBKDF2-SHA256. The salt and iteration
  count are stored in plaintext next to the artifact. They are not secret.
- **AAD binds the blob to its id and version.** The server cannot serve version 2's blob as
  version 3 or swap one artifact's blob into another's URL without the tag check failing.
- **One key per artifact, fresh nonce per version.** The link stays the same across updates.
  Random 96-bit nonces are safe for far more versions than any artifact will have. A private
  artifact gets a new key after someone loses access (see Revoking), so it can hold several keys,
  one per generation.
- **The title is inside the envelope.** The server learns only the blob size, the owner and
  timestamps.
- **v2 compresses before encrypting.** Ciphertext doesn't compress, so HTML used to travel at
  full size. gzip, because every browser decodes it natively (`DecompressionStream`) and Go has
  it in the standard library; brotli and zstd have no universal native browser decoder. The
  client keeps gzip only when it lands in a smaller padded size, so already-compressed media and
  small pages are stored raw. The JSON is capped at 5 MiB (the largest blob) before compression
  and after decompression, so a small blob can't inflate into a large one.
- **v2 pads to Padmé buckets.** Compressed size says how repetitive a page is. Padding the inner
  plaintext to Padmé (Nikitin et al., PETS 2019) leaves O(log log n) bits of the length for at
  most 12% extra, where power-of-two buckets cost up to 100%. Everything up to 4 KiB pads to
  4 KiB. v1 content was not padded at all.
- **Old clients are told to update.** A blob's magic is plaintext, so the server records each
  version's format. Clients that open v2 ask for blobs with `?envelope=2` (a query parameter, as
  the request may redirect to signed storage, where a custom header would need CORS). Without it,
  a v2 blob answers 426 "update madal", which older CLIs print as is.
- **Owners repack old versions lazily.** When the owner's client (CLI, SDK, MCP or browser) opens a
  v1 version, it seals the same content as v2 under the same key and replaces the blob in the
  background, after the page is shown. `PUT .../versions/{n}/blob` takes only the owner, the
  version's key generation, a v2 body, and `If-Match` with the version's `rev`; the rev moves on
  each replacement, so a second device's stale repack is refused. Readers never write. A password
  version repacks only once its password was entered. The server can't check the content is
  unchanged; only the owner, who could publish a new version anyway, can do this.
- **Public pages** are plaintext and stay stored as is; the content server gzips them over HTTP.
- **Markdown renders in the CLI** (goldmark) into a full HTML document before encryption. The
  viewer only ever handles HTML, which keeps the browser code small.

The browser mirrors this in `web/app/crypto.js`. `internal/envelope/testdata/vectors.json` holds
vectors produced by the Go code. A Node test decrypts them with the same `crypto.js` the viewer
ships, so a drift between the two implementations fails CI.

## Two origins

Artifact HTML is untrusted code, often agent-written, sometimes hostile. It must never run on the
origin that holds sign-in state or API tokens.

```
app origin      madal.facets.cloud           -> cloudrun "app"      (MODE=app)
content origin  madal.facetsusercontent.cloud -> cloudrun "content" (MODE=content)
```

Both run on Firebase Hosting. Former addresses (the `*.web.app` names, and
`madal-content.facets.cloud` for content) still answer, with a 301 to the same path on the current
host (OLD_HOSTS); browsers keep the `#key` across the redirect.

User content lives on its own registrable domain, `facetsusercontent.cloud`, as Google's does on
`googleusercontent.com`. Madal can't scan encrypted pages, so a phishing page published as a link
is possible. If Safe Browsing flags the content host, the flag stays on that
domain and doesn't reach `facets.cloud`. The two origins are also cross-site to the browser.
Artifacts are isolated from the app as follows:

- Every content-origin response carries `Content-Security-Policy: sandbox allow-scripts
  allow-popups allow-popups-to-escape-sandbox`, so artifact code runs in an opaque origin. Its
  requests are cross-site and never carry the session cookie, it can't read or set cookies, and
  CORS keeps it from reading API responses. A link the artifact opens in a new tab loads as a
  normal page, not inside the artifact's sandbox, so a site it links to works as it would from
  any other page. That tab's opener is the opaque-origin frame, which can't reach the app.
- The session cookie is host-only (no `Domain`), `Secure`, `HttpOnly` and `SameSite=Strict`, so it
  is only ever sent to `madal.facets.cloud`.

The app itself still sits under `facets.cloud`, so any other `facets.cloud` subdomain could set a
`Domain=facets.cloud` cookie named `__session`, which madal would receive. Whoever controlled
such a subdomain could sign a visitor into the attacker's own madal account (login CSRF). The
usual fix, a `__Host-` cookie name, isn't available, because Firebase Hosting forwards only a
cookie named `__session` to Cloud Run. The risk rests on facets.cloud's other subdomains staying
trustworthy; artifact code can no longer be one of them.

Viewing a link-tier artifact:

1. The browser loads `/a/<id>` on the app origin, a static shell.
2. The shell reads the key from `location.hash`, fetches the blob from `/api/a/<id>/blob`, asks
   for the password if the artifact has one, and decrypts.
3. The shell creates `<iframe sandbox="allow-scripts allow-popups allow-popups-to-escape-sandbox" src="<content>/frame">`.
   Without `allow-same-origin` the frame runs in an opaque origin.
4. The frame page sends `ready`. The shell posts the plaintext HTML to it, and the frame swaps
   it in with `document.open()` / `document.write()`. The key never leaves the shell.

The frame response carries
`Content-Security-Policy: form-action 'none'; frame-ancestors <app origin>; base-uri 'none'` and
nothing that restricts scripts. Agent artifacts load Tailwind and chart libraries from CDNs, and
blocking that would break the main use case. The sandbox already denies cookies, storage,
top-level navigation and access to the parent. `form-action 'none'` stops credential-phishing
forms.

The landing page's demo is one HTML file with its scripts inline (`web/app/media/demo/`, served
at `/demo/`). It never runs with the app origin's privileges: its response carries
`Content-Security-Policy: sandbox allow-scripts`, and the landing page frames it with
`sandbox="allow-scripts"`, so it gets an opaque origin with no access to the app's cookies,
storage or keys, even when opened directly. It loads nothing but its own audio. The landing page
itself keeps the shell's policy, plus `frame-src 'self'` for that frame.

Both clients decrypt with the artifact id and version they asked for, and refuse an answer that
names a different one, since the AAD binds both and a server could otherwise pass one version off
as another.

Public artifacts skip the decrypt step. `/p/<id>` on the app origin is a shell with OG tags,
and its iframe points at `<content>/p/<id>/raw`, which serves the HTML directly under the same
CSP plus a `sandbox allow-scripts allow-popups allow-popups-to-escape-sandbox` CSP directive.

### Printing and Save as PDF

The page can't print from its own frame. `print()` in a sandboxed frame needs `allow-modals`,
which would also let page code raise `alert()` and `prompt()` over the viewer, a phishing aid
("re-enter your madal password"). Printing from the shell's tab is worse: Chrome's default footer
prints the tab's URL, `#key` included, so anyone handed the PDF could open the page. So the viewer
prints from a separate window:

1. Print / Save as PDF in the ⋯ menu, or Cmd/Ctrl+P on the shell, opens `<content>/frame/print`
   with `window.open` inside the click, so pop-up blockers and iOS allow it. The URL has no page
   id and no key.
2. The shell asks the page's frame for a snapshot. A script injected next to the password guard
   (`web/app/print.js`) clones the rendered DOM. Canvases become `<img>` data URLs. `<style>`
   elements take their rules from the CSSOM, where CSS-in-JS libraries put them. `<script>`,
   `<noscript>`, frames, `<object>`, `<embed>`, `<base>`, `<meta http-equiv>`, `on*` attributes
   and `javascript:` values are dropped.
3. The print window says it's ready to its opener, on the app origin only. The shell posts it the
   snapshot. The window takes it only from `window.opener` with the app origin, parses it with
   `DOMParser`, drops the same elements again, swaps it in, waits for fonts and images (10 s at
   most), calls `print()` and closes on `afterprint`.

The window's CSP is `sandbox allow-scripts allow-modals; script-src 'sha256-…'; object-src 'none';
base-uri 'none'; form-action 'none'; frame-ancestors 'none'`. The hash is of the one inline
script in `web/content/print.html`, computed from the rendered page at startup, so nothing in a
snapshot runs there, inline handlers included. `allow-modals` is safe here because only madal's
script runs. The viewer's frame keeps its old sandbox, with no `allow-modals`.

The print CSS sets `@page` margin boxes: an empty header, and "n / N" in the footer. Chrome then
drops its own header and footer and doesn't offer the option. Firefox has no margin boxes yet
(bz 856371), so its footer prints this window's URL, `<content>/frame/print`, which carries
nothing secret.

Threat notes:

- The page's own scripts share the frame, so they can answer the snapshot request themselves. They
  get their own page printed, with nothing run. Forged `madal-print-ready` messages are ignored,
  since the shell checks `e.source` against the window it opened.
- What prints is a snapshot. Pages that keep drawing after load (WebGL, timers, video), content in
  shadow roots, and cross-origin frames inside the page print as they stood or not at all. A
  canvas that drew another site's image can't be read and prints blank.
- The shell gives up after 15 s with no snapshot (a page that replaced its document with
  `document.open()` loses the listener) and closes the window.
- iOS Safari is untested. A top-level print window avoids the iframe print bug there, and Share >
  Print stays as the fallback.

## Accounts and tokens

- **Web sign-in.** Google, GitHub or an emailed magic link, through Firebase Authentication with
  a per-app Identity Platform tenant. `GOOGLE_SIGNIN=1` and `GITHUB_SIGNIN=1` show those buttons.
  The sign-in page trades the Firebase ID token for a `__session` cookie, the only cookie
  Firebase Hosting forwards.
- **Only verified emails count.** Sharing finds people by email, so the server trusts an address
  only when Firebase marks it verified. Google and email links verify it; GitHub may not, and
  then the sign-in page sends a confirmation email and waits. Until an account's email is
  verified it can't start a session or set up keys, lookups skip it, and invites to that address
  stay hidden from it. Without this, someone could claim an address they don't own, set up keys,
  and receive the shares meant for its owner once the owner verifies it.
- **One account per email.** If someone who signs in by email link later picks Google or GitHub,
  Firebase refuses the second account. The page emails a sign-in link to that address and, after
  it's opened, offers to add the provider to the existing account. Only the provider's name waits
  in `localStorage`, never a credential.
- **`madal login`.** The CLI starts a loopback listener on `127.0.0.1:<random>`, makes a PKCE
  verifier, and opens `https://<app>/cli/login?port=…&state=…&challenge=…`. The page signs the
  user in, calls `POST /api/cli/codes` with the ID token and the challenge, and redirects to the
  loopback with a one-time code. The CLI exchanges code plus verifier at `POST /api/cli/token`
  for an API token. A code is single-use, expires after 2 minutes, and is useless without the
  verifier.
- **API tokens** are `mdl_` + 32 random bytes, base64url. The server stores SHA-256 hashes only.
  The CLI keeps the token in the OS keychain (`go-keyring`).
- **Tokens expire when idle.** A browser session lasts 30 days and a CLI token 90, each renewed
  once it's past half its life and still in use. Tokens issued before expiry existed count from
  their creation. `POST /api/me/signout` (and `/api/web/logout` for the browser) deletes the token
  on the server; `{"everywhere": true}` deletes every token on the account. `madal logout` calls it
  before clearing the keychain, and `madal logout --everywhere` ends every session. A browser
  sign-out must carry our own `Origin`, so another site can't sign people out.
- **Publishing needs an account** with a verified email (from 14 October 2026), so every page
  belongs to someone who can be held to it. Before that, an anonymous publish returned an edit
  token, hashed the same way, so the publisher could update or
  delete without an account.

## Data model

Firestore through its MongoDB API. Blobs go to GCS.

```
users      {_id: uid, email, created_at}
tokens     {_id: sha256(token), uid, created_at, expires_at, label}
cli_codes  {_id: sha256(code), uid, challenge, expires_at}
artifacts  {_id, owner_uid | null, edit_token_hash | null, tier, latest,
            password: {salt, iterations} | null, title (public only),
            description (public only), key_gen, rotate, first,
            created_at, updated_at, changed_at, last_comment_at, expires_at | null}
removals   {_id: "<owner uid>/<artifact id>", owner_uid, artifact_id, at, expires_at}
versions   {_id: "<id>/<n>", artifact_id, n, size, object, key_gen, created_at,
            note (sealed) | null, author_uid, via_agent, pruned}
reports    {_id, artifact_id, reason, key_included, created_at, ip_hash}
limits     {_id: "<scope>/<key>/<window>", count, expires_at}

gs://<bucket>/a/<id>/<n>        link-tier ciphertext or public plaintext
```

Artifact ids are 16 random bytes in base64url (22 chars). Guessing one is not feasible, but an
id alone reveals nothing for the link tier anyway.

**Dashboard polling.** The dashboard checks for changes at most once a minute while someone is
looking (web/app/refresh.js). Its own-pages list is the one that grows with a person's history, so
after the first check it asks only for what changed: `GET /api/artifacts?since=<cursor>`. The
answer is `{artifacts, removed, cursor, full}`. Every store write to an artifact record sets
`changed_at` by the store's clock, and `updated_at` keeps its meaning as the page's age. A page that
leaves its owner's list, because it was deleted or an org admin took it over, leaves a record in
`removals`. The cursor is the store's clock when the call began, never the client's. Each call looks
back two minutes before it, so a write stamped by an instance whose clock runs behind still shows;
the client merges by id, so seeing a page twice costs nothing. An empty cursor, more than 500
changes, or a cursor older than the 30 days removals are kept all get the whole list with
`full: true`. A call without `since` is the plain list, byte for byte as before, for the CLI, MCP
and dashboards from before this. The shared, teams and invites lists are still read whole on every
check.

**Indexes.** Firestore's MongoDB API answers a query with no matching index by scanning the
collection, and bills reads for what it scans. Without indexes, every poll reads every artifact in
the database, not only the caller's. The app server creates the ones the store's queries need when
it starts (`EnsureIndexes` in internal/store/indexes.go):

- `artifacts {owner_uid: 1, updated_at: -1}` for the plain list
- `artifacts {owner_uid: 1, changed_at: 1}` for `?since=`
- `removals {owner_uid: 1, at: 1}` for `?since=`
- `comments {artifact_id: 1, created_at: 1}` for a page's comments, whole or `?since=`

It lists each collection's indexes first and creates only the missing ones, matching on keys, so
a start that finds them all creates nothing. Firestore takes one index per `createIndexes`, and
refuses a `maxTimeMS` over 60 seconds, which the Go driver sets from the context deadline. So
each index is its own call, all at once, under a 50-second deadline, in the background. Firestore
builds an index as a long-running operation, a few minutes at least, and queries keep working
(by scanning) until it's ready. Creating indexes needs `roles/datastore.indexAdmin` on the app's
service account, scoped to this database with the same IAM condition as its `datastore.user`
grant. Without it the server logs a warning and carries on. Check an index is ready with
`skoop debug gcloud firestore indexes composite list --database=<database id>`.

A TTL policy on `removals.expires_at` can drop old removal records. Nothing depends on it.
`TestPollReads` in internal/store measures what each query examines on MongoDB, with and without
the indexes.

**Store operators.** Production runs on Firestore's MongoDB API, which doesn't implement every
MongoDB operator. Store code uses only the operators below, which production has run. Using any
other one (`$push`, `$addToSet`, `$size`, `$exists`, `$ne` and so on) means first proving it on
Firestore, then adding it here.

- Updates: `$set`, `$unset`, `$inc`, `$max`, `$setOnInsert`.
- Filters: equality, `$in`, `$gt`, `$gte`, `$lt`.

A write that changes one array, such as an org's admin chain, a team's departed list or a page's
owner changes, is a compare-and-swap on a counter kept next to it (`admins_rev`, `departed_rev`,
`owner_rev`). It filters on the counter's value as read, then `$set`s the new array and `$inc`s
the counter. A counter at 0 is a missing field (omitempty), so a write that expects 0 first sets
it with `$max: {counter: 0}` instead of filtering on `$exists: false`. Folder tag revisions and
version repack revisions work the same way. A query that would need `$ne`, `$exists` or a
comparison between two fields (an org is a team whose `org_id` is its own `_id`) reads with a
plain filter and drops the rest in Go.

## Abuse controls (v0)

- Publishing needs a signed-in account with a verified email; the server refuses anything else
  with 401. Encrypted pages can't be scanned, so accountability is the main defence: an abusive
  account can be banned and all its pages removed. Anonymous artifacts from before this expire
  within 7 days of creation; they can be deleted with their edit token but take no new versions.
- Size caps: 1 MiB per version anonymous, 5 MiB signed in. An artifact keeps its newest 5
  versions (see Older versions), so one artifact holds at most 25 MiB.
- Rate limits in fixed windows stored in `limits`: 10 publishes an hour per IP anonymous,
  60 an hour per account; per account an hour, 20 new teams, 200 team member changes and 600
  shares. The client IP comes from `X-Forwarded-For` as set by Firebase Hosting; an IPv6 address
  counts by its /64. Anonymous limits fail closed when the counter store is down; account limits
  fail open, so an outage doesn't stop people who are signed in. The stored IP hashes are keyed
  with `IP_SALT`, which the app server requires on real storage.
- Caps: 100 teams per account, 500 members per team, 500 shares per artifact. Team names have no
  control or invisible formatting characters, and the CLI also escapes them when it prints. Vault
  password iterations are between 600k and 10M.
- An anonymous artifact expires at most 7 days after it was created, however its limits change.
  Public pages take no open limit, since they are served without counting opens.
- A report button in the viewer chrome. For link-tier artifacts the reporter can tick a box to
  include the key, which is the only way the operator can ever read reported content.
- Expiry is enforced on read. Expired artifacts return 410 and get deleted lazily.

## Sharing with people and teams

Agreed 2026-10-11. A link can leak; a share to a named person or team can't, because its link
carries no key. The artifact is sealed exactly as for the link tier. What changes is how its content
key `K` reaches the reader: instead of riding in the fragment, `K` is wrapped to the reader's public
key and stored on the server as a **grant**. The server holds grants it cannot open.

Tiers after this change: **private** (people and teams only, no key in the link), **link**
(anyone with the full link), **public** (plaintext). Blog posts, when they come, are public.

### Keys

Every account has two P-256 key pairs, generated on the user's device:

- `E`, ECDH, for receiving wrapped keys.
- `S`, ECDSA, for signing team keys.

P-256 rather than X25519 because WebCrypto and Go's standard library both support it everywhere
Madal runs. Public keys are stored on the server in the clear.

Each account signs its own `E` public key with its `S` key, and the server stores the signature
(`e_sig`) next to the keys:

```
e_sig = ECDSA-P256-SHA256(S, "madal/v1/ekey/" + uid + "/" + hex(E_pub)), raw r||s
```

So a client that trusts someone's `S` key (pinned, or listed in an org's signed admin chain) can
check that the `E` key the server hands out is theirs before wrapping anything to it. New keys are
signed when they're made. Keys from before this get signed the first time a current CLI or
browser unlocks them (`PUT /api/me/keys/esig`; the server checks the signature first). In the CLI
that's any signed-in command with keys on the machine, `whoami` and `login` included, and the
first tool call of `madal mcp`. Once the server is known to hold a signature for these keys the
CLI notes it in `trust_seen.json` and doesn't ask again.

### The vault

The private halves of `E` and `S` live on the server inside a **vault**: PKCS#8 bytes sealed with
AES-256-GCM under a random 32-byte vault key `VK`. `VK` is wrapped with a key derived from two
secrets, as in 1Password's two-secret key derivation: the **master password** and a **Secret
Key**, 16 random bytes made on the user's device when the vault is created and never sent to
the server:

```
secret unlock    W = PBKDF2-SHA256(master password, salt16, 600000 iterations, 32 bytes)
                     XOR HKDF-SHA256(Secret Key, salt = uid, info = "madal/v1/vault/secret-key", 32 bytes)
wrap             "MDW1" || nonce12 || AES-256-GCM(W, nonce, VK, aad = "madal/v1/vault/" + uid)
Secret Key text  "M1-" + base32(16 bytes), grouped 6-5-5-5-5
```

- Signing in (Google, GitHub or an email link) and unlocking are separate. Sign-in proves who you are to the
  server; only the master password and the Secret Key together open the vault.
- A stolen copy of the server's data can't be opened by guessing the master password: each guess
  would also need the Secret Key's 128 random bits. The master password must still be at least 12
  characters, and 600,000 PBKDF2 iterations slow any guess.
- Each browser keeps the Secret Key (IndexedDB) after the first unlock, and `madal login` hands it
  to the CLI's keychain with the private keys, so it's typed once per device, from the **Emergency
  Kit** the vault page shows at setup (print it, or save it in a password manager). Signing out
  keeps it, as 1Password does; `madal logout --forget` removes it.
- Vaults from before Secret Keys have a `password` wrap (`W` from the password alone). The browser
  replaces it with a `secret` wrap at their next unlock: the same `VK` and account keys, so no grant
  changes, and the Emergency Kit is shown then. The server accepts exactly one of the two.
- Losing the master password or the Secret Key loses everything encrypted for that account.
  Nobody can recover either, Madal included. "Start from scratch" deletes the account and
  everything in it, as Bitwarden does, and the user signs up again.
- The vault format allows more wraps of `VK` (the server accepts a `passkey` kind). Unlocking
  with a passkey, via the WebAuthn PRF extension, is planned and not offered yet.
- The CLI gets the private keys during `madal login`: it puts a throwaway ECDH public key in the
  sign-in URL, the browser unlocks the vault and wraps the private keys to that key, and the
  wrapped blob comes back through the one-time CLI code. The CLI keeps the keys in the OS keychain.

### Wrapping a key for someone

```
eph            = fresh P-256 key pair
Z              = ECDH(eph.private, recipient.E.public)
W              = HKDF-SHA256(ikm = Z, salt = eph.public || recipient.E.public,
                             info = "madal/v1/wrap/" + context)
wrapped        = "MDK1" || eph.public(65) || nonce12 || AES-256-GCM(W, nonce, K, aad = context)
context        = "<artifact id>/<recipient kind>/<recipient id>"    (grants)
                 "team/<team id>/<member uid>"                       (team keys)
```

The context in both the HKDF info and the AAD means the server can't move a grant to another
artifact or another recipient.

### Teams

Removed 2026-11-20. People share with their org or with people by email. The server answers 410
"teams were removed; share with your org or with people" to making a team (`POST /api/teams` for
anything but an org) and to adopting one, and the CLI, MCP, web app and skill no longer offer them.
Teams already stored keep serving their pages and still take removals, rotations and deletes; no
data was migrated, since production had none in use. Orgs are team records underneath, so the
machinery below still runs every org.


- A team has its own `E` pair. Its private key is wrapped (above) to each member's `E`, so adding a
  member is one wrap and gives them every artifact already shared with the team.
- Every change to the team key is a signed **transition**. The admin who makes it signs, with
  their `S`:

  ```
  "madal/v2/teamkey/" + team id + "/" + version + "/" + signer uid + "/" + change + "/"
    + hex(prev) + "/" + public key
  change = "create" | "remove:<uid>" | "resign"
  prev   = SHA-256 of the previous transition's message (empty for "create")
  ```

  The account's trust record (Trust records, below) keeps the last transition it accepted per
  team and refuses an older version (a rollback), a different key at the same version (a fork) or
  a next version whose `prev` doesn't match. A new signer, such as a second admin, stops the CLI
  and the viewer until the user accepts it; the CLI shows the signer's fingerprint and takes
  `--accept-new-key`. An account that has never seen a team trusts the first transition it sees.
- **Removing a member rotates the team key.** The remover's device makes a new team key, wraps it to
  the remaining members, and re-wraps every team grant from the old key to the new one, then
  deletes the old grants. The removed member keeps what they already opened and nothing new.
- **A rotation only wraps to members this device has seen.** The member list comes from the server,
  so a member this device has no key on record for (say, one another admin added) stops the
  rotation with their fingerprints, and it goes ahead with `--accept-new-key` after the user checks
  them. Otherwise a server could list a member of its own and receive the new team key.
- One concept, "team". No nesting, no workspaces in v0.
- **Teams live in orgs** (agreed 2026-11-17). Only an org admin can make a team, and the server
  refuses a `create` whose signed transition doesn't name an org the caller admins. A team made
  before this rule, outside any org, stays readable, pages and all, but takes no new members,
  invites or pages until an org adopts it (below). Personal accounts share page by page: with
  people, with links and with passwords.

### Orgs

- An org is a team record whose key transitions name it as its own org. A team made inside an org
  names the org too, so its transitions use a v3 message, and members refuse a team whose org
  changes:

  ```
  "madal/v3/teamkey/" + team id + "/" + org id + "/" + version + "/" + signer uid + "/" + change
    + "/" + hex(prev) + "/" + public key
  ```

  Teams outside any org keep the v2 message. Org keys, members, invite links, expiry, re-issue and
  rotation all reuse the team code.
- **Admins are a signed chain.** Each link lists every admin with the signing key they use, carries
  the hash of the link before, and is signed by an admin of that earlier link (the first by its only
  admin, the creator):

  ```
  "madal/v1/orgadmins/" + org id + "/" + seq + "/" + signer uid + "/" + hex(prev) + "/"
    + join(sorted(uid + ":" + hex(s_pub)), ",")
  ```

  The server checks each new link and keeps org roles in step with it. Clients check the whole chain
  and pin the last link, refusing a rollback, a fork or a different first link. An org's key must be
  signed by someone in the chain, and only an admin in it can sign an org invite, which the invitee's
  client checks.
- **The org owns its teams.** A team made in an org is wrapped to every org admin when it's made,
  and every team key goes to a new admin when they're promoted. Org admins are admin members of
  every team, so they invite, remove and delete as team admins do. A team member's client accepts a
  team key rotated by an org admin without asking. Org members see only the teams they're in.
- **Org admins manage the org's pages.** A page with a grant to the org or to one of its teams
  (filed in its drive, or shared with it) can be changed by any org admin as if they owned it:
  new versions, restores, deletes, sharing, tier and limits. They already hold every team key
  and the org key, so they open the page's keyring through the team's grant and encrypt new
  versions under it; if the key has to rotate, they re-wrap it for every grant as the owner
  would. Each version records who published it, so the history names the admin. Pending email
  invites stay with the owner: each link's secret is wrapped to the owner alone, and a claim
  needs the inviter to own the page. So an admin's version that needs a new key stops while any
  are pending, naming them, rather than leave those links unable to open what comes next. The
  admin can cancel them (taking access away is always allowed), ask the owner, or take the page
  over, which ends them. Admins can't invite by email for the same reason. In the browser they
  file the page into the org's drives (which shares it), remove people and teams, and delete it.
  A page with no such grant (a
  member's personal page) stays the owner's alone. Everyone else who can read the page comments
  on it, as before.
- **Taking a page over.** When an owner leaves, an org admin can make the page theirs
  (`madal takeover`, the `org` tool's `takeover`, or the viewer's Take over button). The server
  moves the owner and records the move, which the page's history shows. The previous owner's own
  grant, their pending invites to the page and their own folders for it go, so they keep only
  what their teams give them, and a private page gets a new key with its next version. The new
  owner's client gives itself a grant to the keyring it opened through the team.
- **Pages pass to the org.** A page shared with an org, directly or through one of its teams,
  belongs to the person who shared it while they're in the org. When they leave it, an admin
  removes them, or they delete their account, the server moves it to the org itself:
  `owner_uid = "org:<org id>"`, which no person's uid matches, so the page leaves their My drive,
  lands in no admin's, and stays in the org drive for every org admin to manage. The move is in the
  page's history with its reason (`left`, `removed`, `deleted`). As with a takeover, their grant,
  invites and folders go and the key rotates with the next version; a link page also becomes
  private, so the same link opens only for the org's members and anyone shared with by name. A
  page also shared with another org they're still in stays theirs. The org's pages can't be taken
  over, take no email invites (an invite's secret is wrapped to one owner's key), and keep the
  org's own grant. `GET /api/orgs/{id}/handover?uid=` counts what would pass, for the leave and
  remove confirmations, and site admins move pages of people who left before this with
  `POST /api/admin/orgs/{id}/sweep-owners` (`?dry_run=1` only counts).
- **Adopting a team.** A team made outside any org (say, before orgs existed) joins one when
  someone who is an admin of both the org and the team adopts it (`madal org adopt <team>`, the
  `org` tool's `adopt`, or the org page). Everyone in the team must already be in the org. The
  team keeps its key, pages and folders. Its next transition, signed by that admin, is
  `change = "adopt:<org id>"`, with the same public key. It keeps the v2 message, since the change
  already names the org, so clients from before orgs still verify the team until its key next
  rotates (from then on its transitions use v3, which those clients can't check, as with any team
  made in an org). The team key is wrapped to every org admin outside the team, and they become
  its admins. The server moves member wraps, grants and team folder blobs to the new key
  version unchanged. Pending invite links were signed for the old version, so they stop working
  and the CLI re-issues them. A client that pinned the team outside any org accepts the move into
  one, but until it has seen the team in the org, it still asks before trusting a new signer.
  A move from one org to another, or out of one, is still refused.
- **One link joins both.** A team link to someone outside the team's org also carries an org invite
  sealed under the same secret (`&org=<id>&ov=<version>`). Only an org admin can make one. The
  server refuses a team join from outside its org.
- **Removal and leaving.** `madal org remove` drops the person from the admin chain if they're on
  it, then rotates the org key and every org team key they held, re-issuing each scope's pending
  links. Leaving deletes the leaver's key copies at once and lists them as departed until an admin's
  remove rotates the keys.
- **Names.** An org's name is sealed with a key derived from the org key (HKDF over ECDH of the org
  key with itself), padded to 64, 128, 256 or 512 bytes, and sealed again on every rotation. The
  server never sees it. Team names are still plaintext until their own migration.
- **Domain claim.** An org gets its domain from its first admin's verified email (one org per
  domain, kept in `domain_claims`). Verifying it with DNS is optional and only adds a tick. An admin
  can DNS-verify only the domain the org already holds by email; an org with none claims its admin's
  email domain first. So two orgs never compete for one domain. The org's root is the SHA-256 of its
  first admin link. `_madal.<domain> TXT
  "madal-org=<org id>; key=<first 16 bytes of the root, hex>"` verifies the domain. The root doesn't
  change when keys rotate or admins change, so the record stays put. The server verifies the record
  only when every resolver it asks (1.1.1.1 and 8.8.8.8, directly) returns it, re-checks daily, and
  drops a verified claim after 7 days missing. Clients look the record up themselves (the browser
  over DNS-over-HTTPS) and compare it with the root they pinned; the tick shows only when both agree.
  For local runs, `DEV_DNS` (allowed only with `STORE=memory`) answers from fixed records or a file.

### Joining an org

Agreed 2026-11-20. Joining takes an admin's approval, replacing invite links for new members.
Org invite links are gone: `PUT /api/teams/{org}/invites` (new or re-issued) answers 410 with
"org invite links were removed: ...", which old clients print. Links already sent can still be
claimed until they expire or a rotation ends them, and a rotation no longer re-issues them. The
CLI has no `org invite`, `invites`, `reissue` or `revoke`, and the MCP `org` tool has no such
actions.
Nobody asks: someone signed in with a verified email at the org's claimed domain (or a subdomain of
it), with keys set up, is listed for the org's admins as waiting. The server lists them when they
set up keys, when their E key gets signed, and when the dashboard asks `GET /api/me/company`. They
need keys whose E key carries a valid signature by their S key, since that is what an admin's
client checks before wrapping. Until an admin adds them, they use madal on their own and see
"Waiting for an admin at <Org> to add you". "Not for work" (`DELETE /api/orgs/{id}/requests/me`)
takes them off the list and keeps them off when they sign in again; `POST /api/orgs/{id}/requests`
puts them back. `GET /api/me/company` returns `join_org_id`, `requested`, `withdrawn`, `declined`
and `preapproved` so the page knows what to show.

Admins list requests with `GET /api/orgs/{id}/requests`: name, email, when, and the requester's
public keys. Approving is the usual member add (`POST /api/teams/{id}/members`): the admin's client
checks the requester's signed E key, pins it, and wraps the org key to it. The server refuses an
org member add whose E key isn't signed, and the add clears the request. Declining
(`POST /api/orgs/{id}/requests/{uid}/decline`) sets the request aside: the person isn't listed
again when they sign in, and can still ask again.

Admins can approve emails ahead of time (`PUT /api/orgs/{id}/preapproved {emails}`, each at the
org's domain, 100 per call and 1000 per org). Once such a person has an account with signed keys,
the request list carries them as `preapproved: true`, whether or not they asked, and the next admin
client to list requests adds them without asking. So a pre-approved person joins as soon as any
admin's browser or CLI runs. `GET /api/teams` gives each org's admins a `requests` count for the
nav badge. Every one of these routes answers 403 to anyone but an org admin, members included.

Requests live in `org_requests {_id: "<org>/<uid>", org_id, uid, email, requested_at, status}`
(status empty while waiting, `withdrawn` or `declined`) and
pre-approvals in `org_preapprovals {_id: "<org>/<email>", org_id, email, by, at}`.

In the CLI that's `madal org join` (`--cancel`), `madal org requests`, `madal org approve
<email>... | --all`, `madal org decline`, `madal org preapprove` (`--remove`) and `madal org
preapproved`; the MCP `org` tool has the same actions. Approving checks the requester's E key
with `checkKnown(strict)`, the check a new admin gets: the signature over E must verify, and the
key is pinned on first sight. Nothing is wrapped otherwise. The pre-approved adds run in the
housekeeping every signed-in command does (`CompleteInvites`, which also runs before each MCP tool
call), for orgs the caller admins whose `requests` count isn't zero, one line per person added.

Teams are gone from the CLI and MCP (agreed 2026-11-20). `madal team` answers "teams were removed;
share with your org or with people", the MCP `team` tool is gone, and `team:` recipients and
`team:` folders are refused; My drive and the org drive stay. Sharing is with people (`--with
a@x.com,b@y.com`, MCP `people`) or with the org (`--org`, `--remove org`, MCP `org: true`).
`share --link` opens a page to anyone with its link, and `share --restricted` takes it back to the
people named: the private tier, and no org grant. Orgs are still team records
underneath, so the key, rotation and invite code stays.

**Shared with.** The page lists show who each page reaches: the owner's list (`GET /api/artifacts`,
the `?since=` delta too) and the org drive's (`GET /api/teams/{org}/pages`, for pages the caller owns
or manages as an org admin) carry `shared_with {orgs: [ids], people: [emails]}`, the owner left out,
from one grant query (`ListGrantsFor`, `$in`). Other readers never get it. Shared with you carries
`via_org` when a page reached the caller through their org. The dashboard shows it as the Shared
with column: the org as a badge, one name or "N people" with the names in a tooltip, or "Only
you". A share doesn't touch the page's record, so the dashboard asks for its whole list after the
share dialog closes.

### Org plans

Every org has a plan, kept in `org_billing` (`internal/store/plans.go`). There's no payment
provider yet. madal's site admins (`ADMIN_EMAILS`) set plans by hand from the admin console's
Orgs tab.

| State | What works |
|---|---|
| `trial` | Everything. A new org gets 14 days, with no card. |
| `active` | Everything. Paid. |
| `comped` | Everything. Free, by a site admin's choice. |
| `read_only` | Members open and read every page. The server refuses new filings into the org's or its teams' drives, new versions and title changes on org-filed pages (so restores too), team and org invites, invite claims (team, and artifact claims on org-filed pages), new members, new teams, adopting a team, admin-list changes that add someone, and new team grants to the org or its teams. Taking pages out, unsharing and deleting still work. |
| `locked` | All of the above is refused, and no page filed in the org or one of its teams opens for anyone, its owner included. The team page listing, the org's team list and the admin invite list answer the same error. |

A page counts as org-filed when it has a team grant to the org or one of its teams, or a folder
tag in an `org:` or `team:` scope of one. A page in two orgs takes the stricter state. Personal
pages, with no org grant or tag, are never affected. Nothing is deleted in any state. The server
decides all of this from metadata it already holds; the content stays encrypted.

The stored `plan` is either `trial` or a state a site admin picked. A trial's state is worked out
when a request needs it (`OrgBilling.State`): before `trial_ends_at` it's `trial`, for the next 16
days (to day 30) it's `read_only`, then `locked`. Nothing runs on a timer. A state a site admin
set stays until they change it.

Refusals are 403 with `{"error": ..., "org_state": "read_only" | "locked"}`. The locked message
is "This org is locked. Contact support@facets.cloud". The CLI and MCP print the server's text.
`GET /api/teams` and `GET /api/teams/{id}` carry the org's `plan` (state, `trial_ends_at`, and
`locks_at` while a trial is running its course). The dashboard turns that into banners
(`web/app/plan.js`). Org admins see the trial's last four days, from day 10. Everyone in the org
sees read-only and locked, since both change what they can do.

Site admin routes, which 404 for anyone else like the other admin routes:

- `GET /api/admin/orgs`: every org by id and claimed domain (the name stays sealed), seat
  count (approved members, admins included), pending count (people waiting for an admin), plan, trial end, last change and who made it, and the last 20 log
  entries.
- `POST /api/admin/orgs/{id}/plan` with `{"action", "days", "note"}`. Actions are `activate`,
  `comp`, `extend` (by `days`, 1 to 365, from the trial's end or from today if it has passed),
  `read_only`, `lock` and `unlock`. Unlock applies only to a locked org and leaves it read-only,
  so members can read and export while the plan gets sorted out. Activate or comp make it work
  fully. Every action appends to `org_plan_log` (actor email, action, from, to, note, time).

`seat_events` is an append-only log of `(org_id, account_id, added|removed, at)`, written where
org membership changes: creating an org, adding a member, claiming an org invite, leaving,
`org remove` (a rotation that removes a current member), and deleting an account. Seat counts
over time come from it later. Nothing reads it yet.

Orgs made before plans existed have no record. The first request that needs one creates a trial
starting at `PLANS_SINCE` (RFC 3339, set it to the deploy time), or at that moment if it's unset,
so existing orgs start their 14 days at deploy, not at creation.

### Trusting public keys

The account's trust record keeps the public keys it has seen for every person, and madal refuses
to share when one changes until the user accepts it. A person's `E` key must carry a valid
signature by their `S` key when they're an org admin (the org's chain vouches for `S`, and only the
signature carries that to `E`), and once the record has seen it signed. A signature that doesn't
verify is always refused. A
dishonest server could still substitute a key on the very first share between two people. That is
trust on first use. To close it, people can compare **fingerprints**:

```
fingerprint = first 16 bytes of SHA-256("madal/v1/fingerprint" || E_pub || S_pub),
              as 8 groups of 4 uppercase hex digits
```

The CLI prints the other person's fingerprint the first time it shares with them, and the new one
when a key changes. `madal whoami` and the keys page show your own; `madal keys fingerprint EMAIL`
shows anyone's. Go (`internal/keys/fingerprint.go`) and the browser (`keys.js`) compute it alike,
and a test pins both to the same value.

Over MCP, an agent can't accept a key. `madal mcp` has no `--accept-new-key` argument, and it
ignores the flag if someone starts it with one. Each new or changed key goes to the user as an MCP
elicitation, which the client puts to the user directly and the model never sees. The question
shows the fingerprint and needs the user's yes, one key at a time (`App.ConfirmKey`). A key the
user accepts is pinned, as with the CLI. If the user says no, or the client can't ask, the tool
stops and returns the fingerprint. Page passwords work the same way. `share` takes
`password: "set"` or `"remove"`, never a password, and madal asks the user for the new password
itself. `get` asks for the password when a page needs one this machine doesn't hold. The
questions travel as the tool result's input requests (MCP multi round-trip), so the client answers
and calls again. For older clients, the SDK asks them directly.

### Trust records

Agreed 2026-11-19, before v0.2.0. Everything a client pins (orgs, teams, people) lives in one
record per account on the server, sealed so only the account's own devices can read or change it.
Pins used to sit on each machine (`known_teams.json` and `known_keys.json` for the CLI,
localStorage `madal.orgs` and `madal.teams` in the browser). Two things went wrong with that.
madal v0.1.30, sharing `~/.madal` with a newer CLI, rewrote `known_teams.json` without the org
fields and locked the user out of their org. And the browser's two stores let a server serve a
pinned team as an org (or the reverse) and get its own key trusted on first use. A record on the
server also follows the account to a new laptop or browser.

```
trust key  = HKDF-SHA256(ikm = ECDH(E_priv, E_pub), salt = E_pub, info = "madal/v1/trust/" + uid)
sealed     = "MDR1" || nonce12 || AES-256-GCM(trust key, padded JSON, aad = "madal/v1/trust/" + uid + "/" + seq)
padded     = JSON || 0x80 || zeros, to 1, 4, 16, 64 or 256 KiB
JSON       = { "v": 1, "uid", "seq", "pins": { "org:<id>" | "team:<id>" | "person:<uid>": pin } }
org pin    = root, admin_seq, admin_hash, version, hash, signer, signer_s_pub, org, at
team pin   = version, hash, signer, signer_s_pub, org, legacy, at
person pin = email, e_pub, s_pub, signed, at
```

- The key comes from `E` the way folder keys do, so the browser derives it from the
  non-extractable key it already holds and the CLI from its keychain copy. A key reset seals the
  record again under the new `E` while the old keys are still kept (`finishReset`).
- The kind is part of each pin's key. An id pinned as a team is never read as an org's pin, and a
  pinned team served as an org (or the reverse) is refused.
- `seq` is in the AAD, so the server can't relabel an old record as a newer one, or move one
  account's record to another. `at` is the seq a pin last changed at.
- `GET /api/me/trust` returns `{seq, blob}`. `PUT /api/me/trust {prev_seq, seq, blob}` is
  compare-and-swap: the server takes it only if its record is still at `prev_seq` and `seq` is
  higher, and then records `trust_seq` on the account's keys (`GET /api/me/vault` returns it).

**Rollback.** Each device keeps the highest seq it has seen (`trust_seen.json` next to the CLI's
keystore, IndexedDB in the browser). These hold no pins, and losing them only weakens the check.
A record below `max(that, trust_seq)` is refused. So is one that doesn't open with the account's
keys.

**Deletion.** If the server has no record but `trust_seq` or the device says there was one, the
client refuses to trust anything on first use. It doesn't quietly start over. The user can start
again on purpose: `--accept-new-key` (an MCP question when it comes from an agent), or "Start a
new trust record" on the org page. A new record starts above every seq seen.

**Older server.** A 404 on `GET /api/me/trust` that the API itself wrote (a JSON error) means
no record yet. A bare 404 means the route is missing: the server is older than the client, as
after a rollback. The client then says so ("this madal server is older than your madal; org and
team features are unavailable until it's updated"), and pins nothing new. It writes nothing,
leaves the seq it saw where it was, and doesn't offer to start again, since there's no record to
start. Personal pages don't use the record and keep working. Once the server is updated the
record is back as it was.

**What's left.** The server holds both the record and `trust_seq`. If it rolls both back
together, or deletes both, a device that has never seen a later seq can't tell: a new device,
or a browser whose storage was cleared. That device sees the older pins, which the account
itself wrote, so it isn't trust on first use, but changes pinned after that point are lost to it
until it sees a later record. Any device that saw the later seq refuses the old one. That
includes the device that wrote it, and every device that loaded the record since.

**Two devices at once.** A write that loses the race gets a 409. The client then reads the new
record and applies its change again, pin by pin. Whichever pin is further along wins: the higher
key version, or the longer admin chain. For a person, the later `at` wins. Two pins that disagree
at the same point (two keys at one version, two admin lists at one length, two first admins, two
orgs) are an error the user sees, never merged.

**Migration.** The first time a device loads the record, it brings its old pins in. Pins the
record already has stay as they are. The CLI reads `known_teams.json` and `known_keys.json` and
never writes them again. It doesn't delete them either: v0.1.30 may still use them, and nothing
newer reads them. A `known_teams.json` entry with no org fields comes across as a team marked
`legacy`. It may be an org whose fields v0.1.30 dropped, so seeing that id as an org pins it
afresh. The browser moves `madal.orgs` and `madal.teams` in, then removes them.

**Old clients.** v0.1.30 never sees the record and can't write it. Whatever it does to the pin
files no longer matters to newer clients.

**DNS-verified orgs.** The DNS record vouches for the root. The trust record still guards the
admin chain and the key versions.

### Inviting people who don't use Madal yet

Sharing with an email that has no keys creates an **invite** instead of a grant. Only the
inviter's device can finish it, because only it holds the artifact (or team) key, so every
`madal` command checks for invites whose invitee has since signed up and set up keys, wraps the
key to them, and deletes the invite. The invitee's first-seen keys are pinned at that moment, the
same trust-on-first-use as any share. Madal sends no email itself: the CLI prints the link for the
user or their agent to pass on.

A team invite also carries an invite link, so the invitee can join with no admin online. The
admin's machine seals the team's private key under a fresh 32-byte secret (AES-256-GCM, bound to
the team id, key version and invited email; `keys.SealTeamInvite`) and signs the invite with the
admin's signing key: team, version, inviter, email, role and a hash of the sealed key
(`keys.TeamInvite`). The secret goes only in the link, `/t/<team>#invite=<secret>`. The server
checks the signature against the admin's published signing key before it stores the invite, so a
stolen session token alone can't make one. It hands the sealed key only to an account signed in
with the invited, verified email, and only while the invite is at the team's current key version
and its inviter is still an admin. The invitee's client checks the team's key signature and chain
as for any team, checks the admin's signature on the invite, opens the sealed key and refuses it
unless its public half is the team's signed public key. Then it wraps the key to itself and joins.
The role comes from the signed invite, never from the claim. Joining adds a member and leaves the
key chain alone, so every member's pinned chain still verifies.

A rotation (removing a member, or a re-sign) kills every pending team link. A rotation usually
follows a removal, and the removed person may have seen the links. The server strips the sealed
key from those invites and answers a late claim with 410, so the old key never reaches anyone.
Then the rotating admin's machine re-issues each pending invite: a fresh secret, the new team key
sealed under it, a signature over the new key version, keeping the invite's email and role. It
stores that with the same admin-only, signature-checked `PUT` as any team invite, which replaces
the old one. The old secret can't open the new blob. A link also carries the key version it was
issued at (`#invite=<secret>&v=<version>`), and the server answers 410 when that doesn't match the
invite's, so an old link gets the same "out of date" answer as before. `madal team remove` prints
the new links. If one re-issue fails, the rotation still stands and that invite is reported for a
manual re-invite. The invite record survives either way, so an admin's machine still completes it
with the current key once the person signs up.

The admin also picks when a team invite expires (7 days unless they say otherwise). The expiry is
part of the signed invite, so the server can't extend it: the invitee's client checks the
signature over it and refuses the invite after it, and the server answers a claim after it with
410. An admin can re-issue an invite by hand: a fresh secret, the current team key sealed under
it, signed, through the same `PUT`, which replaces the stored invite. The invite stores an id of
the link's secret (`keys.TeamInviteLinkID`, a hash, so the server still can't open anything), and
the client sends it when it fetches the invite. A link whose id doesn't match gets 410 "replaced",
so a re-issue kills the old link even at the same key version. A re-issue keeps the old expiry
unless that has passed. Rotation re-issues keep each invite's expiry too, and leave an expired
invite for an admin to re-issue. Revoking (`POST /api/teams/{id}/invites/{email}/revoke`) keeps
the invite record without its key, so its link gets 410 "cancelled" and no admin's machine
completes it, until the email is invited again. Because re-issuing replaces an invite that already
exists, it still works after the invitee signed up, where a new invite would be refused with
"share with them directly".

Each team invite also stores its secret wrapped to the issuing admin's own key
(`keys.TeamInviteOwnerContext`), as artifact invites do. The admin-only `GET
/api/teams/{id}/invites` returns that copy only to the admin who issued it, and only while the
invite is live at the current key. The team page in their browser unwraps it and shows the link
with a copy button. The server can't open the copy.

### Limits and access

- `--expires` deletes an artifact after a time (anonymous artifacts: at most 7 days).
- `--max-opens` stops a link after that many opens. The owner's opens don't count, and the counter
  only runs while a limit is set, from when it was set.
- `share --access only-people|link` switches a non-public artifact between the private and link
  tiers. Old full links stop opening once it's private. Moving to or from **public** isn't allowed:
  public is plaintext, so the honest way is to publish again.

### Deleting an account

`DELETE /api/me`, with the account's email in the body as confirmation, first passes the account's
pages shared with its orgs to those orgs (see Pages pass to the org), then purges every artifact the
account still owns (blobs, versions, grants), deletes its received grants, invites by or for it, team
memberships, sharing keys, every token (CLI and browser sessions alike), the user record and the
sign-in record. A team it leaves is deleted if empty; otherwise its longest-standing member becomes
admin if none is left. The server can't rotate team keys, so a team whose key was signed by the
departed admin needs re-signing by the next admin: a new team key under that admin, for the same
members, with every team grant re-wrapped to it. The admin's device asks first (the command stops
and says so, and `--accept-new-key` goes ahead), since the server could fake a departed signer.

### Recovery on another machine

Every artifact an account publishes while it has sharing keys gets an **owner grant** (its key,
wrapped to the owner like any reader) and, from v0.1.15, an **encrypted title**: the title
padded to 64, 128 or 256 bytes (`0x80` then zeros), sealed `"MDT1" || nonce12 ||
AES-256-GCM(K, nonce, padded, aad = "madal/v1/title/" + id)` with the artifact's newest key. The
server can read neither. On a machine where the account is unlocked, `madal list` rebuilds the
local record of every artifact it doesn't know (title and full `#key` link) from these.

Artifacts published before the account had keys on a machine have no owner grant. Every signed-in
command backs a few of them up quietly (owner grant and title), and `madal logout` backs up the
rest first.

`madal logout` then drops what the server can rebuild (local records, the private keys) and keeps
the Secret Key and anything that can't be rebuilt: records of artifacts published without an
account, whose edit token only that machine holds. `--forget` drops those too, after listing
them, with the Secret Key and the fingerprints this machine has verified.

### Folders

An owner files their pages into folders: path tags such as `work/clients/acme`, split on `/`. A
page can carry several. There is no folder record; the tree is whatever the owner's pages are
tagged with, built on the client, and a folder exists while some page carries it. Renaming a
folder rewrites the tag on every page under it, from the client.

Tags are sealed with a **folder key**, never the page key, so the people a page is shared with
can't read how its owner files it:

```
folder key = HKDF-SHA256(ikm = ECDH(d, d·G), salt = d·G, info = "madal/v1/folders/" + scope)
tag blob   = "MDF1" || nonce12 || AES-256-GCM(folder key, nonce, padded JSON list,
                                             aad = "madal/v1/tags/" + scope + "/" + id)
```

`d` is the scope's private key: the account's E key for `user:<uid>`. Agreeing the key with its
own public key needs no storage and works with WebCrypto's non-extractable keys, so every machine
and browser where the account is unlocked derives the same key. The JSON list is padded to 128,
512 or 2048 bytes (`0x80` then zeros), so the server learns neither the names nor how many tags a
page has. The AAD binds a blob to its scope and page, so it can't be moved to another one.

The server keeps one blob per scope in the artifact's `tags` map (`PUT /api/artifacts/{id}/tags`).
It can't search or filter by folder.

**Drives.** Each scope is a drive: `user:<uid>` is My drive, `team:<id>` a team drive, and
`org:<id>` the org drive. Clients write a folder with its drive: `my:drafts/x`,
`team:eng/specs/2026`, `org:handbook`; a bare path is in My drive. A team or org drive's blob is
sealed with a folder key derived as above from the team's or org's private key, so every current
member derives it and nobody else can. The scope's kind must match the record: an org's drive is
always `org:<id>`, never `team:<id>`.

| Scope | Who may write it | Who gets it back |
|---|---|---|
| `user:<uid>` | the page's owner, their own scope only | the owner |
| `team:<id>` | any member of the team, once the page has a team grant | members of that team |
| `org:<id>` | any member of the org, once the page has a grant to the org | members of that org |

Each scope's blob has a revision (`tag_revs`). A write names the revision it replaces and gets 409
if someone wrote first; the client re-reads, replays its edit (what it added and removed) on the
current tags, and tries again. So two members filing one page at once don't drop each other's
folders. Clearing a scope keeps its revision counting, so a writer still holding a revision from
before the clear can't write over it.

Filing a page into a team drive is two writes: the owner's client grants the page to the team (if
it isn't already), then writes the tag. A member who isn't the owner can file, re-file and unfile a
page the team already has, but can't share or unshare it. When the owner takes a page out of its
last folder in a team drive, the client deletes the team's grant if filing made it, and the server
drops the team's tag blob with it; unsharing from a team by any route does the same. Each team
grant records whether filing made it (`via_filing`): a page the owner shared with the team on
purpose, before or after filing it, stays shared when it leaves the drive.

A team key rotation (removing a member, or re-signing) changes the team's folder key, so the
rotating admin's client opens every team tag blob with the old key and re-seals it under the new
one, in the same request as the grant re-wraps. The server checks the request covers exactly the
pages that have a blob, at their current revisions. A blob the old key can't open is re-sealed
empty rather than blocking a removal.

The store has no multi-document transactions (Firestore's MongoDB API), so a rotation writes in an
order it can be re-run from. Each team blob records the key version that sealed it (`tag_vers`).
The re-sealed blobs go first, and each keeps the blob it replaces in `tags_prev`, so both key
versions' blobs sit on the page and readers open whichever their key opens. Next the store
re-checks the team's pages: one filed with the old key in the meantime fails the rotation with
409. Then the member wraps and grants are written, and last the team record with the new key
version and the member's removal. A rotation that fails (a 409 on a racing filing, say) leaves the
team on its old key with the member still in it, and running the removal again completes: it
re-seals from the old-version blobs. The server refuses a team tag write whose `key_version`
isn't the team's current one, so a member on a retired key can't file under it. One gap remains:
the member wraps and grants are overwritten in place, so a store failure between those writes and
the team record can leave a mix that a re-run can't repair.

The folder key follows the account key. After a key reset, the first machine that still holds
the old key re-seals the tags when it takes the new keys at login, as it re-locks the owner
grants. The resetting machine keeps the old private key, sealed in the vault next to the new one
and in its keychain, until every grant and tag is re-sealed. The move skips what has already
moved, so if it fails partway the old key stays and the next unlock or login carries on; only
then is the old key dropped. If no machine holds the old key, the folders are gone.

A client from before folders doesn't re-seal tags, so a reset from it would lose every folder
name. Clients that move folders say so with `?folders=1` on `PUT /api/me/keys`, the same way
`?envelope=2` says a client opens v2 blobs. The server refuses a reset without it (426, telling
the user to run `madal upgrade`) when any of the account's pages has a tag blob in its own drive.
An account with no folders can still reset from an old client.

### Revoking

Removing a person or team deletes their grant. The CLI matches the name against the artifact's own
grants, so an owner can remove a team they've since left, and it prints exactly which grants went.
Removing a team doesn't remove a member's own direct grant, and the output makes that visible. The
server then stops serving them any version. What they already opened, they may have kept, and the
product says so rather than implying otherwise.

They may also have kept the key. So deleting a grant on a private artifact marks it for
**rotation**, and the next real update uses a new key:

- The server holds the state: `key_gen` (the current generation) and `rotate`. While `rotate` is
  set it only accepts a version at `key_gen + 1`, sent in the `Madal-Key-Gen` header; that version
  moves `key_gen` up and clears `rotate`. Otherwise a version must use the current `key_gen`.
- Before uploading, the publishing device resolves every remaining recipient, checking pinned keys
  and team transitions. If any check fails, it stops before anything changes. Then it re-wraps the
  whole **keyring** to each of them and uploads the version under the new key. Old versions keep
  their old keys and aren't re-encrypted, so remaining readers keep the history. A removed reader
  can't open anything published after their removal, even with the old key in hand.
- A keyring is one of:

  ```
  key(32)                                     generation 0 only, as grants were before rotation
  "MDR1" || count(1) || keys                  generations 0 to count-1
  "MDR2" || first(2, big endian) || count(1) || keys
                                              generations first to first+count-1
  ```

  Each version records its generation and readers pick `keyring[key_gen]`. The `MDR2` form drops
  generations that only deleted versions used. A rotation trims them, so a ring never holds more
  than about one key per kept version. Grants are capped at 4 KiB, which is plenty.
- The owner's grant carries the ring too, so the owner's other machines read the current ring from
  it, not from a local copy that may be stale. That is also how a second machine updates an
  artifact it didn't publish.
- An invite completed later gets the full ring.
- Link-tier artifacts don't rotate, since the key is in every copy of the link. Once a private
  artifact has more than one key, it can't switch to link tier, because a link carries one key.

### Older versions

An artifact keeps the content of its newest 5 versions. Publishing the 6th deletes version 1's
blob, and so on, so the link never stops taking updates. Version 1's record stays, marked
`pruned`, as page history (see Page history). The artifact's `first` is the oldest version
kept. Asking for an older one's content gets a 404 that says it was deleted.

Every kept version stays readable to anyone who can read the artifact. The viewer has a "Version n
of N" menu listing the kept ones. Each pick opens in a new sandboxed frame. If a version has a different password, the viewer
asks for it again. A slow earlier pick never replaces a later one. `madal get <link> --version n`
does the same from the CLI.

## Page history

Agreed 2026-11-17. A reader sees a page's versions with time, author and note, and compares any
two kept versions, Google Docs style. Full design: `docs/design/page-history.md`.

- **Notes.** Optional, for humans and agents alike: a subject of at most 120 characters, then an
  optional body. The publisher seals the note with that version's content key, so a password
  version's note needs its password:

  ```
  pt    = subject [+ "\n\n" + body] || 0x80 || zeros, to 256, 1024 or 4096 bytes
  note  = "MDN1" || nonce12 || AES-256-GCM(EK, nonce, pt, "madal/v1/note/" + id + "/" + version)
  ```

  It travels in a `Madal-Note` header (std base64) on the version PUT. The server checks only its
  magic and padded size. `internal/notes` and `web/app/notes.js` share vectors.
- **Authorship.** Each version records its author and `via_agent` (a CLI or API token, not a
  browser session), the rule comments use. The author's name shows where "Shared by" would.
- **History outlives pruning.** `GET /api/artifacts/{id}/versions` lists every record, pruned ones
  marked `kept: false`, to anyone who can read the page. Public pages have no history.
- **Diffs are computed on view, never stored.** The client diffs the two versions' source line by
  line (a Markdown page's source is the HTML madal rendered it to) with Myers' diff, capped at 2000
  edits, and shows it the way git does: old and new line numbers, 3 lines of context, unchanged
  stretches folded, and the changed words within a paired changed line marked. If either version
  has a line over 1000 characters, both are broken before each opening block tag first, so a page
  written on one line still diffs by line; the line numbers are then those of the broken source.
  The viewer shows the diff as text in the shell, never in the page's frame. It draws at most 1000
  rows of a stretch at a time, with a button for the rest. `internal/pagediff` and
  `web/app/diff.js` share vectors. `madal diff` and the MCP `diff` tool give the same diff as
  `diff -u` text. Fetching an older version to compare counts as an open, as viewing it does.
- **Since you last looked.** The browser keeps the last version it showed per page in
  `localStorage`, and offers the comparison when the page has moved on. It never reaches the server.
- **Restore.** Owner only: the client re-encrypts an old version under the current key (and
  password) and publishes it as a new version noted "Restored vN".

## Comments

Agreed 2026-11-11. Readers comment on a page inside the viewer: on a passage, a whole element or a
dragged area, with one level of replies. Comments are sealed with a key derived from the page's
key, so whoever can read the page can read its comments and the server can't:

```
CK     = HKDF-SHA256(K[key_gen], info = "madal/v1/comment", 32 bytes)
body   = "MDC1" || nonce12 || AES-256-GCM(CK, nonce, JSON {text, anchor, mentions?}, aad)
aad    = "madal/v1/comment/" + artifact id + "/" + version + "/" + comment id + "/" + parent id
proof  = base64url(HKDF-SHA256(K, info = "madal/v1/comment-auth/" + artifact id))
anchor = {exact, prefix, suffix}                      a passage (W3C text quote)
       | {pin: {path, tag, x, y, w, h, ew}}           an element or area, as fractions of the element
```

- The comment id is chosen by the browser because it's in the AAD; the parent id binds a reply to
  its thread. The server can't move a comment to another page, version, id or thread.
- The anchor is inside the ciphertext, since a quoted passage is page content. The frame finds it
  again in whatever version is shown; one it can't find shows as outdated, never deleted.
- Commenting needs a signed-in, verified account. Private pages check the reader's grant. A link
  page's readers also send the proof, and the server keeps only its SHA-256, set by the owner's
  browser the first time the owner opens the page, so knowing a page id isn't enough. Public and
  password-protected pages take no comments.
- Roles (2026-11-22). Each grant, by name or to an org or team, has a role: `comment` (the
  default, and what a grant from before roles, with none, means) or `view`. A `view` grantee reads
  the page and its comments, and deletes their own, but the server refuses (403, "you can view
  this page but not comment on it") their posts, replies, resolves and reopens. With several
  grants (by name and through an org) the strongest role wins; the owner and managing org admins
  always comment. `GET .../comments` answers `can_comment` so the viewer hides its comment box
  for view-only readers; `GET .../mentionable` leaves view-only readers out, and gives them an
  empty list. `PUT /api/artifacts/{id}/grants` takes `role` (empty on a re-wrap keeps the stored
  one), `PUT .../grants/{kind}/{rid}/role {role}` changes it (owner or managing admin), and an
  email invite keeps `role` until it becomes a grant. The CLI's `madal share ID --with x --role
  view|comment` sets it, sharing again changes it, and the MCP `share` tool takes `role`. On a
  link page, "Anyone with the link" maps onto the comment proof: Can view is `DELETE
  .../comment-auth`, which stores a marker no proof matches and that the automatic turn-on (the
  owner opening or commenting) won't replace; Can comment is `PUT .../comment-auth {hash, on:
  true}`. The role is metadata next to the grant, which the server already holds; no content
  reaches it.
- The server stores the author, the version, the key generation, the time and whether a thread is
  resolved, and who resolved it. Anyone who can comment on the page resolves or reopens any thread
  on it, and the thread shows who resolved it. Deleting an account keeps its comments without an
  author.
- The CLI, the Go SDK and `madal mcp` read and post comments with the same crypto
  (`internal/comments`, kept in step with `comments.js` by shared vectors in its `testdata/`). On a
  link page the CLI sends the proof, and when its owner finds no proof hash stored yet, it stores
  one the way the owner's browser does. `madal comment --on "passage"` builds the anchor from the
  latest version's text the way the frame indexes it: text under `<body>` minus script, style and
  noscript, with 32 characters either side.
- Posting a comment sets the page's `last_comment_at` to the comment's own time (it only moves
  forward) and its `changed_at`, so the owner's next `?since=` poll returns the page. `updated_at`
  stays the page's age. The own, shared and team or org drive lists send `last_comment_at`; the
  single-page read, which anyone holding a link can make, doesn't. The shared list also sends
  `shared_at`, the time of the grant the page came through. `GET .../comments?since=<cursor>`
  answers only comments from the cursor on, with the same checks as the whole list and the same
  two-minute look-back as the dashboard poll; every answer carries the next cursor, and the client
  merges by id. A `since` answer doesn't show deletions or resolves. This lets a dashboard find the
  few pages with new comments and decrypt only those. None of it is new to the server: it already
  stores each comment's page, author and time, and each grant's time. `last_comment_at` is the
  newest of those times, kept on the page.
- A comment posted with a madal token in the `Authorization` header (the CLI, SDK or MCP server)
  is stored with `via_agent`; the browser sends its session cookie instead. The viewer shows a
  "via agent" badge next to the author, so readers know a program posted it for that person.
- @mentions (2026-11-21) work on org pages only: pages shared with an org, or an org's team, that
  the commenter is in. `GET /api/artifacts/{id}/mentionable` lists that org's other members (uid,
  name, email), which members already see in the org; every other page gets an empty list, and "@"
  stays plain text. Typing "@" and letters in a comment box offers matches; Tab or Enter fills
  "@Name". On posting, each "@Name" that names a member is sealed into the body as
  `mentions: [{uid, name}]`, so the server never learns who was mentioned, and readers see the
  names highlighted. Those are whatever the commenter sealed, so a reader highlights a mention
  only when its uid is someone the page lists under that same current name, and the banner and
  the Inbox count a mention of you only under your current name; anything else is plain text. The key is left out when there are none, so older clients and the shared
  vectors are unchanged. There's no email or other channel. The viewer tells people itself: when
  a signed-in reader opens the page and comments decrypt, a banner says "You were mentioned in N
  threads" for mentions of their uid that are still unread in their Inbox (see Inbox below). Show
  opens the panel at the first one, and their own name stands out in it. Once the banner shows,
  those mentions count as read in the account's sealed inbox state, so the banner and the Inbox
  agree on every device. Without that state (keys locked here, or the network), every mention not
  shown on this visit shows.
- Pages shared with people by name (2026-11-21) take @mentions too: the list adds the page's owner
  and the people it's shared with by name, besides the caller. People invited by email who have no
  account yet aren't listed.
- Emails on comments (2026-11-21): each comment carries its author's email, and the mention list
  has one for everyone in it, so two people with the same name can be told apart. Hovering an
  author or an @mention shows it, and the "@" list shows it under the name. A caller gets an email
  in full only where they already see it: their own; everyone's when they manage the page (its
  owner, or an org admin over it, as in the share list); other members of the page's orgs they're
  in; and the owner's verified email on a private page ("Shared by"). Everyone else's comes masked
  by the server, first character and domain (`c•••@example.com`), so a full address never reaches
  a reader who isn't allowed it. Where two people share a name, a posted "@Name" mentions the one
  picked from the list, not whoever comes first.
- Comment text never enters the sandboxed frame, where the page's own scripts run. The frame reports
  positions (selection, clicks, element boxes) and paints highlights with the CSS Custom Highlight
  API; the viewer draws tooltips, cards, regions and markers above it and treats everything from the
  frame as untrusted.

## Inbox

Agreed 2026-11-21. The dashboard's Inbox lists @mentions of you, replies in threads you started or
replied in (from your first comment in the thread on), and pages shared with you by name. Pages
that reach you through a team or your org aren't items: filing a page into the org drive shares it
with the whole org, which would flood everyone. Comments on pages you own are off by default; a
checkbox in the Inbox turns them on, per browser. It shows the last 30 days, at most 100 items.

The server learns nothing new. It never sees an inbox:

- The browser finds the items. The page lists carry `last_comment_at` and the shared list carries
  `shared_at` (see Comments). On each dashboard check (the same 60s, visible, not idle rules), the
  browser picks the pages whose `last_comment_at` moved since it last looked, fetches their
  comments (the whole list the first time on a visit, so an old thread you started still counts,
  then `?since=` the cursor), opens them with the page key it already opens for titles, and keeps
  who wrote each one, when, in which thread and whom it mentions. It drops the text. A quiet day
  costs nothing extra. It finds items only while a dashboard is open, and catches up on the next
  visit.
- Read and dismissed state is one sealed record per account, `GET/PUT /api/me/inbox-state`, built
  like the trust record: `keys.InboxKey` from the account's E key, padded, bound to the uid and a
  `seq`, written compare-and-swap. Inside: a `floor` time (items at or before it are read), `read`
  and `unread` marks newer or older than it, and `dismissed`, each mark with its time. Item ids are
  the comment id, or `share:<page id>`. Two devices merge mark by mark (`web/app/inboxstate.js`):
  the later floor, the union of dismissals, and the newer mark per id. The server sees only the
  record's size bucket and when it's written, which tells it roughly when you read your inbox.
  The server can't forge the record but could replay an older one, bringing read items back as
  unread, so each browser remembers the highest `seq` it has seen per account (localStorage
  `madal.inbox.seq.<uid>`) and refuses a lower one.
- The tab's dot and the Inbox count are worked out in the browser. Until it has decrypted, the dot
  comes from the count this browser saved last time (localStorage, never synced). No count comes
  from the server.

The pure part is `web/app/inbox.js` (pick pages, find items, group rows, keys, swipes), tested in
`inbox.test.mjs`. The view lives in `dashboard.js`:

- "Inbox" sits at the top of the Madals sidebar, above My drive, at `#pages/inbox`. One list, one
  row per page: unread rows first in bold, then read ones, newest activity first in each. A row
  shows the title, who ("Alice and 2 others"), a reason chip (Mention, then Reply, Shared, Comment),
  how many items, and how long ago. Filter chips: All, Mentions, Replies, Shared.
- A row opens its page at the newest unread comment and marks the row read first. The link carries
  the comment in the fragment, `#~c=<comment id>` (or `#<key>.<token>~c=<id>` on a link page), so
  the server never sees which comment you went to. The viewer takes it off the address at once and
  calls `jumpTo` once the comments load.
- Each row toggles read or unread and dismisses. On a desktop, checkboxes select rows for a bulk
  mark or dismiss. "Mark all read" moves the floor and offers Undo for 5 seconds, which marks the
  same items unread again. Keys: `j`/`k` move, Enter opens, `u` toggles read, `e` dismisses, `x`
  selects; ignored while typing.
- Phones: the Madals tab in the bottom bar gets the dot, a line "N unread in Inbox" sits above the
  pages list (where the sidebar is hidden), and a row swipes right to mark read, left to dismiss.
- "Shared with you" and "No folder" have their own icons, so neither looks like the Inbox.
## Meeting pages

Agreed 2026-11-20. The madal menubar app records a call, transcribes it on the Mac and publishes
the transcript as a private page. The user's own agent summarizes it later, through the MCP. The
server must not learn which pages are meetings, so a meeting is an ordinary private page plus one
sealed record, `enc_meta`:

```
meta = {kind: "meeting", status, started_at, duration_s, app, tags}
blob = "MDM1" || nonce12 || AES-256-GCM(K, nonce, JSON padded to 256, 1024 or 2000 bytes,
                                       aad = "madal/v1/meta/" + artifact id)
```

`K` is the page's newest key, the same key `enc_title` is sealed with, and the padding is the
title's (0x80, then zeros). Status is `transcript_only`, `summarized` or `no_summary_needed`.

- It is a new field, not the `user:` folder tags blob. Folder tags are sealed with a key derived
  from the account key, so an account key reset has to re-seal them, and clients from before this
  would show a meeting's record as a folder. A page-key blob needs neither: the owner's other
  machines already open the page key through the owner grant, a key reset re-wraps that grant, and
  a key rotation keeps the old keys in the ring, which `openMeta` tries newest first.
- `PUT /api/artifacts/{id}/meta` stores it. Only the owner may set it, on a private or link page,
  at most 2048 bytes. The owner gets it in the list, `?since=` changes and
  `GET /api/artifacts/{id}`. Anyone else who can open the page gets it from
  `GET /api/artifacts/{id}` only, so a person the meeting is shared with sees the meeting view; it
  is sealed with the page key they already hold, so the server still learns nothing. Setting it moves
  `changed_at`, so the dashboard poll sees a status change, and not `updated_at`, because no
  version changed. Old clients ignore the field.
- Every list, filter and count is computed on the client after decrypting: `madal meetings`, the
  MCP `meetings` tool and `whoami.pending_meetings`. The cost is one list call, and the list is
  capped at 500 pages, like `madal list`.
- The page is rendered by madal from one fixed template (`internal/meeting`), never written by an
  agent. The transcript (`turns[{t, speaker, text}]`) and the agent's notes are checked against a
  strict schema. Notes v2 have a title, an optional 1-2 sentence TL;DR, topic `sections[{heading,
  bullets[{text, sub?}]}]`, optional decisions, the participants named in the call, and action
  items with an optional free-text owner and due date, shown as "Next steps". Notes without
  sections are v1 (summary, decisions, items with a required owner), so old pages and agents keep
  working. Every field is plain text, every field is escaped, and the validated JSON sits in the page in a
  `<script type="application/json">` block, so a re-render starts from it rather than from HTML.
  The Notes and Transcript tabs are radio inputs and `:checked`, with no script, since the page's
  hash holds the link key.
- Action items are comment threads, one per item, whose text starts with "Action item". The
  template gives each item `id="item-N" data-item="N"`. On a page whose sealed record says
  `kind: "meeting"`, and only there, the viewer injects a small script into the frame that reports
  where each item's box is, and draws a real checkbox above it. The box is ticked when the item's
  thread is resolved; ticking it resolves or reopens the thread, or first posts one ("Action item:
  <text>. Owner: <owner>", without the owner when the item has none) pinned on the item when it has none. A thread maps to an item by its
  pin on the item's element first, then by its quote equal to the item's text, so pages from
  before the ids work too. Readers who can't comment see the boxes read-only, and a ticked box
  says who resolved it. Nothing new is stored: the thread's resolved flag is the state. Since
  the box already marks the thread, an item thread's quoted text gets a faint wash of its
  commenter's colour instead of the full highlight; other comments on the page keep theirs.
- Setting `no_summary_needed` publishes no version. Summarizing publishes the next version and
  sets `summarized`; a dismissed meeting can still be summarized.
- madal tells the agent a meeting waits in three ways. The hook shows "madal: 1 meeting ready to
  summarize." and tells the agent to ask, in its own words, whether to summarize the meeting (by
  title) now. Any yes starts it, inline, in every agent. The hook text is short and leaves the
  steps to the skill. Claude Code's auto permission mode judges the first step after a bare yes.
  In local trials (`claude -p --permission-mode auto`, isolated config, no allow rules) it let that
  step through in 12 of 16 runs inline and 9 of 21 for a background agent, and blocked a background
  agent in 6 of 6 when the hook spelled out every step. It blocks the dismiss after "no summary
  needed" too (5 of 5). So Claude Code is told that when the check blocks a step it says, in one
  line, to say "summarize it" (or "dismiss it"). Naming the action got through in 19 of 19 runs
  across this and the earlier one-word trials. The MCP reply line and the skill
  say the same, and that only a yes to the agent's own question counts. Codex treats that line as
  tool output and doesn't relay the question, so agents without hooks may not ask.
- Several agents on one Mac can hear about one meeting. Before summarizing a waiting meeting, an
  agent calls `meeting` with `action: "claim"`. madal seals status `summarizing` with
  `claimed_at`, `claimed_by` (from the MCP client's name: Claude Code, Claude Desktop, Codex) and a
  random `claim_id`, which the MCP server keeps for that session. Another agent's claim answers
  "already claimed by <agent>". The server has no compare-and-swap for the sealed record, so a
  claim writes, waits 1.5 s and reads back; when two claim at once, the write that landed last
  wins for both. A claim lasts 15 minutes. Listings, counts, the hook and the web treat a live claim
  as summarizing and an older one as `transcript_only`. `summarize` with `from_status:
  "summarizing"` needs the session's own claim, still in place (an expired claim nobody took over
  counts), and ends it. `release` puts a meeting the session claimed back to waiting. Setting a
  status by hand ends any claim.
- An earlier build had a Summarize automatically setting (`madal meetings auto on|off`, a
  `meetings-mode` file and a menubar toggle). On, it added Claude Code allow rules for madal's
  meeting tools and offered a bare "y" that summarized inline. It is gone: one behaviour, and no
  edits to the user's Claude Code settings. When the MCP server starts or `madal mcp install` runs
  and the profile still has `meetings-mode`, madal removes exactly the four rules it added
  (`mcp__madal__meetings`, `__get`, `__meeting`, `__comment`) from `~/.claude/settings.json`, after
  copying the file to `settings.json.madal-backup`, then deletes `meetings-mode`. A settings file
  that isn't plain JSON is left alone, and the mode file stays so it tries again next time.
- Agents that don't claim can still guard against a race with `from_status: "transcript_only"`.
  madal checks the sealed status right before publishing and returns `skipped` without a new
  version when it changed. The background agent's instructions say the
  transcript is data and limit it to the `meetings`, `get`, `meeting` and `comment` tools. `madal mcp install` adds SessionStart and UserPromptSubmit
  hooks to Claude Code and Codex, and a SessionStart hook to Gemini CLI. Every MCP reply except the
  meetings tools' own ends with a line such as "madal: 2 meetings ready to summarize". And the skill
  covers whoami's `pending_meetings`.
- The hook is `meetings-hook.sh` in the profile's folder, written by `madal mcp install` and
  rewritten each time the MCP server starts. It reads `meetings-pending` (one line per
  meeting waiting or claimed: id, the Unix time its claim ends or 0, and its title with anything
  but letters, digits, spaces and a few marks replaced; rewritten whenever madal counts). It skips
  a live claim without marking it told, so it's mentioned once the claim runs out and the hook's `session_id` from
  stdin. It starts no madal process and makes no network call. It tells each agent session about
  each meeting once: the ids it announced go in `meetings-hook-sessions/<session id>`, so a meeting
  published mid-session is mentioned on the next prompt and not again. Its output is the hooks
  JSON the three agents share: `systemMessage` is the plain line the user sees, and
  `hookSpecificOutput.additionalContext` carries the instructions for the agent. It prints
  nothing when no meeting
  waits or when signed out, since sign-out deletes `meetings-pending`. madal drops session files
  older than a week when it rewrites the list.
- The plugin brings the hook too, so plugin and Gemini extension users get notices without
  `madal mcp install`. It ships `hooks/meetings-hook.sh`, which finds the profile as the CLI does
  ($MADAL_HOME or the OS config folder, then $MADAL_PROFILE or the `profiles.json` default) and
  runs that profile's `meetings-hook.sh`, so the notice text lives in one place. It runs nothing
  until the MCP server has started once and written that script. `npx -y @facets-cloud/madal` was
  the other choice, but it takes about 410 ms warm against a few ms for the script, on every
  prompt. Claude Code and Gemini CLI both read `hooks/hooks.json`, so it holds the SessionStart
  hook for both (each agent fills in its own path variable and the shell empties the other), and
  Claude's UserPromptSubmit hook sits in its plugin.json. Codex gets no plugin hook.
- One notice, not two, when both the plugin and `madal mcp install` added the hook: the plugin's
  script exits when the agent's own settings (Claude's `settings.json` in `$CLAUDE_CONFIG_DIR` or
  `~/.claude`, Gemini's `~/.gemini/settings.json`) already hold the `madal-meetings-hook` entry.
  The per-session file alone isn't enough: Claude Code runs the two hooks at the same moment, and
  both print before either records the meeting. `packaging/plugin/claude-e2e.sh` checks this in
  a real Claude Code with a throwaway config.
- Cursor has session and prompt hooks too, but its `additional_context` doesn't reliably reach the
  agent yet, so madal doesn't install one there.
- Agents without usable hooks (Claude Desktop, Cursor, Windsurf) get two more notices from the MCP
  server itself. When it starts, the server's instructions add a line naming the waiting meetings:
  the count and up to 3 titles from `meetings-pending`, never ids, and to ask the user early on
  whether to summarize them. The server waits up to 300 ms for its startup recount, then reads
  the file as it is, and leaves the line out when the file is missing (signed out, or nothing
  ever counted) or more than a day old. The instructions are fixed for the connection, so a
  meeting published mid-session still reaches these agents only through the reply line.
  The `summarize-meetings` prompt (argument `meeting`: an id or part of a title) is the user
  asking: it lists the `transcript_only` meetings from the server when signed in, else from
  `meetings-pending`, with ids and titles, and the steps from the skill. `meeting-action-items`
  is fixed text asking the agent to list the unresolved "Action item:" threads on summarized
  meetings.

## Out of scope for v0

Blog mode, workspaces, live updates, remote MCP, the verifier extension, paid plans and
`install --harness all`. See the task brief.

## Known limits

- The viewer JS comes from the server. A malicious operator could ship JS that leaks the
  fragment. That is the standard limit of browser E2EE. The planned verifier extension is the
  answer, and v0 does not claim to solve it.
- Public-tier OG cards are text only (title and description). Image cards come later.
