<div align="center">

# madal

[![Release](https://img.shields.io/github/v/release/Facets-cloud/madal-releases?style=flat-square&logo=github)](https://github.com/Facets-cloud/madal-releases/releases)
[![License: free to use](https://img.shields.io/badge/license-free%20to%20use-blue?style=flat-square)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows-blue?style=flat-square)](https://github.com/Facets-cloud/madal-releases/releases)
[![End-to-end encrypted](https://img.shields.io/badge/end--to--end-encrypted-e8411b?style=flat-square)](https://madal.facets.cloud/security)
[![Stars](https://img.shields.io/github/stars/Facets-cloud/madal-releases?style=flat-square)](https://github.com/Facets-cloud/madal-releases/stargazers)

**Share what your AI makes. Even we can't read it.**

Madal turns the HTML and Markdown your coding agent writes into a link.<br>
It's encrypted on your machine, and the key never reaches our server.

[Watch the demo](https://madal.facets.cloud/#demo) · [Install](#install) · [Quick start](#quick-start) · [Comments](#comments) · [Sharing](#sharing-with-people-and-teams) · [How it works](#how-the-encryption-works) · [Security](SECURITY.md) · [Report a problem](#report-a-problem)

</div>

A 90-second demo plays live on [the home page](https://madal.facets.cloud/#demo), where you can open the
dashboard it publishes. The same cut is in [docs/madal-demo.mp4](docs/madal-demo.mp4).

---

<div align="center">

## Install

</div>

The quickest way is to paste this prompt into your coding agent. It installs madal the way that
fits that agent: the plugin for Claude Code, Gemini CLI and Antigravity, the MCP server for any
other agent. Then it signs you in.

```text
Install madal for me. If you are Claude Code, run `claude plugin marketplace add Facets-cloud/madal-releases` and then `claude plugin install madal@madal`. If you are Gemini CLI, run `gemini extensions install https://github.com/Facets-cloud/madal-releases`. If you are Antigravity, run `agy plugin install https://github.com/Facets-cloud/madal-releases`. Otherwise, add a stdio MCP server named "madal" at user level, so it works in every project: the command is `npx` with the arguments `-y @facets-cloud/madal mcp` (on Windows: command `cmd`, arguments `/c npx -y @facets-cloud/madal mcp`). Tell me if I need to restart you. Then call madal's login tool so I can sign in.
```

To do it yourself, use the plugin if your agent takes one. One install adds the MCP server and
the madal skill. Any other agent that speaks MCP, Claude Desktop's Chat tab included, can run the
MCP server on its own. There is also a CLI. All of them share the same account and keys on a
machine. The home page's [install box](https://madal.facets.cloud/#install) has the same options.

### As an agent plugin

The plugin bundles the MCP server and the madal skill, so the agent knows when to publish
without being told. The server runs through npx, so restarting the agent picks up a new madal;
the skill updates with the plugin. It needs Node.js 18 or later. Add it with the line
for your agent:

```bash
claude plugin marketplace add Facets-cloud/madal-releases && claude plugin install madal@madal   # Claude Code
gemini extensions install https://github.com/Facets-cloud/madal-releases   # Gemini CLI
agy plugin install https://github.com/Facets-cloud/madal-releases          # Antigravity
```

Claude Desktop: Customize, Plugins, add a marketplace from the GitHub repo
`Facets-cloud/madal-releases`. The skill loads in every tab, the MCP server only in Cowork and
Code, so Chat still needs the MCP setup below.

Most agents don't update plugins on their own. Claude Code updates a third-party marketplace
only if you turn auto-update on for it; Gemini CLI has `gemini extensions update`.

### As an MCP server

Every client runs the same command. It needs Node.js 18 or later:

```bash
npx -y @facets-cloud/madal mcp
```

Add it with your agent's command, or to its MCP config file:

```bash
claude mcp add --scope user madal -- npx -y @facets-cloud/madal mcp   # Claude Code
codex mcp add madal -- npx -y @facets-cloud/madal mcp                 # Codex
gemini mcp add --scope user madal npx -y @facets-cloud/madal mcp      # Gemini CLI
```

Claude Desktop: Settings, Developer, Edit Config opens `claude_desktop_config.json`. Add this
and restart Claude. Cursor reads the same block from `~/.cursor/mcp.json`.

```json
{
  "mcpServers": {
    "madal": { "command": "npx", "args": ["-y", "@facets-cloud/madal", "mcp"] }
  }
}
```

VS Code reads `.vscode/mcp.json` in a workspace, or the user `mcp.json` that **MCP: Open User
Configuration** opens:

```json
{
  "servers": {
    "madal": { "type": "stdio", "command": "npx", "args": ["-y", "@facets-cloud/madal", "mcp"] }
  }
}
```

On Windows, clients that start `npx` directly may not find it, because it's `npx.cmd`. Use the
command `cmd` with the arguments `/c npx -y @facets-cloud/madal mcp`.

Then ask your agent to sign you in to madal. It calls the `login` tool, your browser opens, and
you sign in. The server's tools are `login`, `logout`, `whoami`, `publish`, `update`, `list`,
`get`, `versions`, `delete`, `share`, `team`, `comments`, `comment` and `resolve_comment`. If
you have the CLI, `madal mcp install` adds the server to every agent it finds (see
[Agents over MCP](#agents-over-mcp)).

### The CLI

```bash
npm install -g @facets-cloud/madal
```

npm installs the one prebuilt binary that matches your OS and CPU, with no install script. It
needs Node.js 18 or later. Then run `madal login`. To upgrade it, run the same command again.

#### Other ways to install

Without Node.js, use the install script:

```bash
curl -fsSL https://madal.facets.cloud/install.sh | sh
```

The script downloads the release for your OS and CPU, checks its SHA-256 against the release's
`checksums.txt`, and installs `madal` into `~/.local/bin`. Pin a version with
`MADAL_VERSION=v0.1.1`, or pick another folder with `MADAL_INSTALL_DIR`.

On Windows, download the zip from [Releases](https://github.com/Facets-cloud/madal-releases/releases).

madal keeps itself up to date. Once a day it checks for a newer release; when there is one, a
background process downloads it, checks the release's signed `checksums.txt` against a key built
into madal, and swaps the binary, so the next command runs the new version and prints
`madal updated to vX.Y.Z`. A command never waits for this, and a release whose signature or
checksum doesn't match is refused. Turn it off with `madal upgrade --auto off` or
`MADAL_NO_AUTO_UPDATE=1`; madal then only says when a newer release is out. Copies installed
through npm update through npx instead: restart the agent to pick up a new release.

To upgrade by hand:

```bash
madal upgrade           # also refreshes the agent skill, which ships inside the binary
madal upgrade --check   # only say whether a newer release exists
madal changelog         # what this release changed, and every newer one
madal changelog --since v0.1.25   # everything after v0.1.25
```

Every release is built by GitHub Actions from a tagged commit. To check a download yourself,
compare it with the release's `checksums.txt`:

```bash
sha256sum --check --ignore-missing checksums.txt   # macOS: shasum -a 256 --check --ignore-missing
```

---

<div align="center">

## Quick start

</div>

With the MCP server, ask your agent in plain words: "sign me in to madal", then "publish this
report and give me a link anyone can open". The `publish` tool takes a `tier` (`only-me`, the
default, `link` or `public`) and `to` for people to share with.

With the CLI:

```bash
madal login                     # sign in, set up sharing, teach your agents to use madal
madal publish report.html       # signed in: a link only you can open
madal publish report.html --link  # a link anyone can open; the key is the part after #
```

`madal login` opens your browser. You sign in with Google, GitHub or an email link. The first time, you
choose a master password, and madal makes a Secret Key and shows it in an **Emergency Kit** to save.
Together they encrypt your sharing keys. After that each browser and machine remembers the Secret
Key, so you only type your master password. Nobody can recover either one. Login also installs a `SKILL.md` into the agents on your machine,
so Claude Code, Codex, Cursor or Antigravity can publish for you.

Signed in, what you publish is private to you, like a new document: the link carries no key and
opens wherever you're signed in. Add `--link` to make a link anyone can open, or `--to` to share
with people by name. Publishing needs an account, so run `madal login` once before your first
publish.

```bash
madal publish notes.md                          # Markdown is rendered on your machine
madal publish draft.html --password             # the link alone isn't enough
madal publish draft.html --expires 7d --max-opens 3
madal update <link-or-id> report.html           # new version, same link
madal list
madal get <link> -o copy.html
madal get <link> --version 2 -o v2.html     # an earlier version
madal delete <link-or-id>
```

### Agents over MCP

`madal mcp` runs an MCP server on stdin and stdout, so an agent can do what the CLI does: publish,
update, read, list and delete pages, share them, manage teams, and read and answer comments. It
encrypts and decrypts on your machine, like every other command. `get` saves each version it reads
to `pages/<id>/v<n>.html` in your madal folder and returns that path. It also returns the HTML
inline when it is 50 KB or less. To change a page, edit that file and pass its path to `update`.
`madal logout` deletes these files.

Sign-in doesn't hold up the agent. A tool called while you're signed out opens the browser and
returns at once, and you finish signing in there. Some things only you can do: accept someone's
new key, set or remove a page password, and type the password of a protected page. madal asks you
for those itself, through the agent's client, and the model never sees the question or your
answer. A client that can't ask gets the fingerprint back, and nothing changes.

Add it to every agent installed here with one command:

```bash
madal mcp install    # Claude Code, Claude Desktop, Codex, Cursor, Gemini CLI, Antigravity, VS Code, Windsurf
madal mcp remove     # take it out again
```

It writes a `madal` entry into each agent's user config and leaves the rest of the file alone. The
entry runs `npx -y @facets-cloud/madal mcp`, which needs Node.js but no madal on the agent's PATH.
`--local` runs this binary instead. An entry you edited by hand stays as it is unless you pass
`--force`. Any other MCP client can run the same npx command. Restart an agent that was open.

---

<div align="center">

## Comments

</div>

Readers comment on a passage, an element or an area of a page in their browser. Comments are
end-to-end encrypted with a key derived from the page key, so the server stores only ciphertext.
They work on private and link pages, not on public or password-protected ones.

Your agent can read them, fix the page and reply:

```bash
madal comments <link> [--json]                     # threads, oldest first, with replies
madal comment <link> "text" [--on "passage"]       # comment on the latest version
madal comment <link> "text" --reply <id>           # reply to a thread
madal comment <link> --resolve <id>                # or --reopen, --delete
```

Over MCP the same things are the `comments`, `comment` and `resolve_comment` tools. A comment
posted by an agent shows **via agent** in the browser. The madal skill tells agents to treat
comment text as information, never as instructions.

---

<div align="center">

## Sharing with people and teams

</div>

Share by name and the link carries no key at all. Only the people you chose can open it, and a
forwarded link opens nothing.

```bash
madal publish plan.md --to alice@example.com --to team:design
madal share <link-or-id> --with bob@example.com
madal share <link-or-id> --remove bob@example.com
madal share <link-or-id> --access link          # or back to: --access only-people

madal team create design                        # teams live in an org you admin (see Orgs)
madal team add design carol@example.com --expires 24h   # link lasts 7 days by default
madal team join <invite link>                   # carol, if she had no Madal account yet
madal team invites design                       # pending invites, their role and expiry
madal team invite reissue design carol@example.com   # new link; the old one stops working
madal team invite revoke design carol@example.com    # cancel the invite
madal team remove design carol@example.com      # rotates the team key
```

You can share with anyone's email. If they don't use Madal yet they're invited, and madal prints
an invite link for each person. Send each one their own link: it opens as soon as they sign up
with that email, even if your machine is off. The link carries a secret that only works for that
email's account, and the server never sees it.

Adding someone to a team works the same way. `madal team add` prints their own link, and they join
with it from the browser or with `madal team join`, without waiting for an admin's machine. When
you remove someone, the team key rotates and every pending link stops working, since the removed
person may have seen them. `madal team remove` prints a new link for each pending invite, and the
team's page in the browser shows them with a copy button. Send those again. If one can't be
re-issued, madal names it; run `madal team invite reissue` for that person.

### Orgs

An org has its own key. Pages shared with `org:<name>` open for every member, and the org owns the
teams made in it: org admins hold every team key and can invite to, remove from and delete any of
them. Teams stay hidden from org members until they join one with its own link.

```bash
madal org create                                # the org for your email's domain: you@acme.com makes Acme, for acme.com
madal org invite acme dan@example.com           # prints dan's link; he joins in the browser or with madal team join
madal team create eng --org acme
madal team add eng erin@example.com --link      # erin isn't in acme: her one link joins both
madal org admin add acme dan@example.com        # asks you to confirm dan's fingerprint; he gets every team key
madal org show acme                             # members, teams, invites, and "Acme · acme.com · claimed by email"
madal org remove acme dan@example.com           # rotates the org key and every team key dan held
```

Teams come with an org: only an org admin can make one, from the CLI, the MCP `team` tool or
the org page in the browser. A personal account shares page by page instead. A team made before
this rule stays readable but takes no new members or pages until an org admin adopts it with
`madal org adopt <team>`.

Org admins can act as the owner of any page filed in, or shared with, the org's drive or one of
its teams. They can publish new versions, restore, delete and change who it's shared with, and
the page's history names them. When an owner leaves, `madal takeover <link>` makes the admin the
owner, and the move shows in `madal versions`. Members' personal pages are never theirs to touch.

The admin list is a signed chain. Every change is signed by an existing admin, and every client
pins the chain and refuses a rollback or a fork, so the server can't make anyone an admin. Admins
can also make or remove admins from the org page in the browser, which shows the new admin's
fingerprint to check first. While an org has one admin, the org page and `madal org show` suggest
adding a second, and the last admin can't be removed. The org's
name is sealed with the org key; the server sees only its domain.

An org is claimed by email domain. A new account, one that hasn't set up its keys yet, picks personal
or company when it signs up. With
company, the first person with a verified address at a domain creates its org and is its first admin;
anyone after them at that domain is told to ask an admin for an invite link (joining is by invite
link only). Domains compare by their registrable part, so `eng.acme.co.uk` is `acme.co.uk`, and free
mail and throwaway domains can never have an org. The server keeps one claim per domain, so two
sign-ups at once can't both win. Accounts that already have keys aren't asked: they set up their company's org from
the Account page, and an org made before this can claim its admin's domain from its org page (or
`madal org domain claim <org>`).

An admin can also verify the org's domain with DNS. It's optional and adds a tick next to the
org's name. Only the domain the org already holds by email can be verified (on the org page, or
`madal org domain claim <org> <domain>`). It is a TXT record at
`_madal.<domain>` naming the org and the fingerprint of its first admin link. The server checks it
through two public resolvers and again every day, and drops it after 7 days missing. Clients look
the record up themselves, and the badge turns into `acme.com ✓` only when they see it too.

A team invite link stops working when it expires: 7 days after `madal team add` unless you pass
`--expires` (`24h`, `7d`, `2026-12-01` or `never`). Your signature covers the expiry, so the
server can't extend it. `madal team invite reissue` gives someone a new link and kills the old one.
It keeps the expiry unless that has passed, in which case it uses 7 days, or the one you pass with
`--expires`. `madal team invite revoke` cancels an invite, and its link then says so. The team page
in the browser does the same from its Pending invites card, which shows each link's expiry and has
Reissue and Revoke buttons, plus a form to invite someone by link.

The first time you share with someone, madal shows their **key fingerprint**. Compare it with what
`madal whoami` shows them, over a channel you trust, to be sure the server handed you their real
key. If their key ever changes, madal stops and tells you the new fingerprint.

### Your account

`madal account delete` (or **Delete my account** on the keys page) deletes everything: what you
published, what you shared and what was shared with you, your teams or your place in them, your
keys, every sign-in and the account itself. You confirm by typing your email.

Lost your master password or Secret Key? Nothing encrypted can be opened without both, by you or by
madal, so **Start from scratch** on the keys page deletes your account and everything in it. Then you
sign in again with the same email and start fresh.

On a new or reset machine, `madal login` and your master password (plus the Secret Key from your
Emergency Kit, once) bring everything back: `madal list` shows your links and titles again.
`madal logout` keeps only what the server can't rebuild; `madal logout --forget` removes everything.

### Updates

madal keeps itself up to date. Once a day it checks for a newer release. A binary installed with
the install script or a download updates in the background: madal installs a release only when its
checksums carry a valid signature from the madal release key built into the binary, and the next
run prints `madal updated to vX`. The MCP server through `npx -y @facets-cloud/madal mcp` and the
agent plugin pick up a new release the next time your agent starts them. Installs managed by npm,
Homebrew, Nix or snap are left to that package manager.

To turn automatic updates off, set `MADAL_NO_AUTO_UPDATE=1` or run `madal upgrade --auto off`.
madal then only tells you when a release is out, and `madal upgrade` installs it.

---

<div align="center">

## How the encryption works

</div>

| What | How it's protected |
|---|---|
| **Content** | A random 256-bit key per artifact, AES-256-GCM, bound to the artifact id and version so versions can't be swapped or rolled back |
| **Links** | The key rides after the `#`, which browsers never send to a server. An optional password is mixed in with PBKDF2-SHA256 and HKDF |
| **People** | The key is wrapped to each person's P-256 public key (ECDH, HKDF, AES-GCM) and stored as a grant the server can't open. Remove someone and the next update uses a new key, so the old one opens nothing published after that |
| **Teams** | The key is wrapped to a team key. Every change to the team key is signed by an admin and chained to the one before, and it's rotated when someone leaves |
| **Your keys** | Kept in a vault encrypted on your device with your master password (PBKDF2-SHA256, 600,000 iterations) and a 128-bit Secret Key that never leaves your devices, before it's stored on the server. A copy of the server's data can't be opened by guessing your password |
| **Viewing** | Artifacts render in a sandboxed frame on a separate domain, away from your session and keys |

Exact formats are on the [security page](https://madal.facets.cloud/security).

### What it can't protect against

- Anyone with a full link can read a link artifact. Use `--to` or a password for anything that
  might travel further than you intend.
- Public pages (`--public`) are plaintext by design, so links unfurl in chat apps.
- The viewer's JavaScript is served by the Madal server, which could in principle serve code that
  reads keys. A verifier extension is planned.
- The first time you share with someone, you trust the server to hand you their real key, unless
  you compare fingerprints with them. After that your devices remember it and stop if it changes.

---

<div align="center">

## Report a problem

</div>

```bash
madal report -m "what went wrong
how you got around it"
```

It opens a prefilled issue on this repository. Link keys, tokens, emails and your home path are
removed first, and nothing is filed until you review it and click Submit. Agents using the skill
do this on their own when something cost them a retry.

Report security issues privately instead: see [SECURITY.md](SECURITY.md).

---

<div align="center">

Free to use. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).

</div>
