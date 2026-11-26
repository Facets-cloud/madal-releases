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

[Watch the demo](https://madal.facets.cloud/#demo) · [Install](#install) · [Quick start](#quick-start) · [Comments](#comments) · [Sharing](#sharing-with-people-and-your-org) · [How it works](#how-the-encryption-works) · [Security](SECURITY.md) · [Report a problem](#report-a-problem)

</div>

A 90-second demo plays live on [the home page](https://madal.facets.cloud/#demo), where you can open the
dashboard it publishes. The same cut is in [docs/madal-demo.mp4](docs/madal-demo.mp4).

---

<div align="center">

## Install

</div>

The quickest way is to paste this prompt into your coding agent:

```text
Set up madal for me: read https://madal.facets.cloud/setup.md (with curl if you can run commands) and follow it.
```

[setup.md](web/setup.md) has one path per agent. Claude Code, Codex, Gemini CLI and Antigravity
get the plugin, with auto-update turned on where the agent supports it. Other agents with a shell
get the CLI, the skill and meeting notices. Claude Desktop can't run commands, so it tells you what
to click. The setup offers the Mac app on a Mac that can run it, and ends by signing you in. The
prompt stays the same when setup.md changes.

To do it yourself, pick the kind that's yours. [Install by hand](https://madal.facets.cloud/install)
on the website has the same options. All of them share the same account and keys on a machine.

### Claude Desktop

You chat in the Claude app and don't use a terminal. Nothing here needs Node.js.

- **Chat:** download [madal.mcpb](https://github.com/Facets-cloud/madal-releases/releases/latest/download/madal.mcpb)
  and double-click it. It's a Desktop Extension with madal built in for macOS, Windows and Linux.
  Desktop shows it as not signed, because madal signs it with its own certificate.
- **Cowork:** Customize, Plugins, add a marketplace from the GitHub repo
  `Facets-cloud/madal-releases`, then install `madal-desktop`.
- **Meetings for Mac:** on a Mac with Apple Silicon and macOS 14.2 or later, get it from the
  [Meetings page](https://madal.facets.cloud/meetings), or ask Claude to "install madal for Mac".

Then ask Claude to sign you in to madal.

### Coding agents

Your agent runs commands in a terminal. Add the plugin with the line for your agent:

```bash
claude plugin marketplace add Facets-cloud/madal-releases && claude plugin install madal@madal   # Claude Code
codex plugin marketplace add Facets-cloud/madal-releases && codex plugin add madal@madal          # Codex
gemini extensions install https://github.com/Facets-cloud/madal-releases --auto-update          # Gemini CLI
agy plugin install https://github.com/Facets-cloud/madal-releases          # Antigravity
```

Claude Code's plugin has the madal CLI and skill, and no MCP server. It installs the CLI, the
Mac app on a Mac that can run it, and meeting notices, and needs no Node.js. The Codex, Gemini CLI
and Antigravity plugins bundle the MCP server and the madal skill, run through npx, and need
Node.js 18 or later.

Most agents don't update plugins on their own. Claude Code updates a third-party marketplace
only if you turn auto-update on for it.

Any other agent with a shell, Cursor included, uses the CLI. Install it (see [The CLI](#the-cli)),
then add the skill and meeting notices:

```bash
madal skills install && madal hooks install
```

To use madal over MCP instead, `madal mcp install` adds the MCP server to every agent it finds.

### Other desktop chat apps

LM Studio, Jan, Msty, Cherry Studio, Raycast and BoltAI run madal as a local MCP server. Install
the CLI, then add this to the app's MCP servers (use `~/.local/bin/madal` if the app can't find
`madal`):

```json
{
  "mcpServers": {
    "madal": { "command": "madal", "args": ["mcp"] }
  }
}
```

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
`get`, `versions`, `delete`, `share`, `org`, `comments`, `comment`, `resolve_comment`, `meetings`,
`meeting`, `install_app` and `enable_meeting_notices`. If
you have the CLI, `madal mcp install` adds the server to every agent it finds (see
[Agents over MCP](#agents-over-mcp)).

### The CLI

On macOS or Linux:

```bash
curl -fsSL https://madal.facets.cloud/install.sh | sh
```

On Windows, in PowerShell:

```powershell
irm https://madal.facets.cloud/install.ps1 | iex
```

The script downloads the release for your OS and CPU, checks its SHA-256 against the release's
`checksums.txt`, and installs `madal` into `~/.local/bin`. Pin a version with
`MADAL_VERSION=v0.1.1`, or pick another folder with `MADAL_INSTALL_DIR`. Then run `madal login`.

To set up everything at once, add `--all`: the binary, the agent skill (into each agent's skills
folder) and, on a Mac with Apple Silicon and macOS 14.2 or later, the madal Meetings app. On other
machines it skips the app and says why. With the madal plugin in Claude Code, `/madal:install`
runs the same command.

```bash
curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --all
```

On Windows, in PowerShell:

```powershell
irm https://madal.facets.cloud/install.ps1 | iex
```

It does the same checks, installs `madal.exe` into `%LOCALAPPDATA%\Programs\madal` and adds that
folder to your user Path, without admin rights. `$env:MADAL_VERSION` and `$env:MADAL_INSTALL_DIR`
work as above; set `$env:MADAL_ALL = '1'` first to also install the agent skill. The Meetings app
is Mac only.

With Node.js 18 or later you can use npm instead, which installs the one prebuilt binary that
matches your OS and CPU, with no install script. To upgrade it, run the same command again.

```bash
npm install -g @facets-cloud/madal
```

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
default, `link` or `public`), `people` for people to share with, and `org: true` for everyone in
your org.

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
opens wherever you're signed in. Add `--link` to make a link anyone can open, `--with` to share
with people by name, or `--org` to share with everyone in your org. Publishing needs an account, so run `madal login` once before your first
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

`update` builds on the latest version this machine published or opened (`get`, `diff`,
`publish`, `update`). If someone else published a newer one since, or this machine never opened
the page, it refuses and changes nothing; get the latest, edit that, and update again.
`--force` publishes on top anyway and replaces their version.

### Agents over MCP

`madal mcp` runs an MCP server on stdin and stdout, so an agent can do what the CLI does: publish,
update, read, list and delete pages, share them, manage your org, and read and answer comments. It
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
madal mcp status     # list the agents it is in
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

## Meetings

</div>

The madal menubar app publishes a call's transcript as a private meeting page. Ask your agent to
"summarize my madal meetings": it reads the transcript, writes notes by topic with a TL;DR,
decisions and next steps, asks you where to file the page and who to share it with, and posts a comment thread for
each action item. madal renders the page itself from those fields, so every meeting page looks
the same. Whether a page is a meeting, and its status, are encrypted with the page.

The app is madal for Mac (Apple Silicon, macOS 14.2 or later). It records a call only after you
click Record and transcribes it on your Mac; audio never leaves it. Download it from the
[Meetings page](https://madal.facets.cloud/meetings), install it from Terminal with
`curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --app`, or ask your agent to "install
madal for Mac". The Meetings page covers the first launch, the permissions it asks for and its
updates.

```bash
madal meetings [--status transcript_only]          # your meetings and their status
madal meetings publish transcript.json             # a new private meeting page
madal meetings summarize <link> notes.json --folder clients/acme
madal meetings status <link> no_summary_needed     # dismiss it; publishes nothing
```

Over MCP these are the `meetings` and `meeting` tools, and `whoami` returns `pending_meetings`.
`madal mcp install` also adds hooks to Claude Code, Codex and Gemini CLI that fire once per
meeting per session. Each shows "madal: 1 meeting ready to summarize.", and the agent asks you in its
own words whether to summarize it now. Say yes, sure or go ahead, and the agent writes the notes in
the conversation, saves the page private and tells you in one line what it saved. Claude Code's
auto permission mode sometimes blocks a plain yes. When it does, the agent tells you to say
"summarize it", which gets through. "Not now" leaves it, and "no summary needed" dismisses it.

Codex runs the hooks only once you trust them, and asks again whenever `madal mcp install` changes them.
Start codex and choose "Trust all and continue" at "Hooks need review", or trust them in `/hooks`.

#### How each agent finds out about a new meeting

| Agent | How it hears |
| --- | --- |
| Claude Code | Hooks, at session start and on each prompt |
| Codex | The same hooks, once you trust them |
| Gemini CLI | A hook at session start |
| Claude Desktop, Cursor, Windsurf and other MCP clients | The MCP server's instructions name up to 3 waiting meetings when the agent connects, the `summarize-meetings` prompt, whose title shows the waiting count, and a line on every madal reply |

Without a terminal, ask Claude Code or Codex to "turn on madal meeting notices". The
`enable_meeting_notices` tool adds the same hooks as `madal mcp install`, to that agent only. With
the madal plugin, the hooks are already there and it changes nothing. Claude Desktop has no hooks:
the tool says so and points to the menu bar line and the prompt.

The `summarize-meetings` prompt ("Summarize madal meetings (2 waiting)") lists the waiting meetings
and asks the agent to summarize them. Claude Code shows it as a slash command, such as
`/mcp__madal__summarize-meetings`, and Claude Desktop in its prompt menu. Claude Desktop keeps the
server running across chats, so the server checks the count every few seconds and after each tool
call, and sends `notifications/prompts/list_changed` when it changes. Give it a meeting's id or part of its title to do just
that one. `meeting-action-items` asks which action items from your meetings are still open.

Several agents on one Mac (Claude Code, Claude Desktop, Codex) hear about the same meeting, so the
one that starts claims it first (the `meeting` tool's `claim` action, or `madal meetings claim`).
The meeting then reads `summarizing`, and the other agents leave it alone until it's summarized,
released, or 15 minutes old.

### The Mac app

It needs a Mac with Apple Silicon and macOS 14.2 or later. Three ways to install it:

- **Download for Mac** on the [Meetings page](https://madal.facets.cloud/meetings): the `.dmg`
  from the latest release. Drag madal into Applications.
- Terminal, which also updates it:

  ```sh
  curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --app
  ```

- Ask your agent: "install madal for Mac". Its `install_app` tool runs only when you ask. It
  checks the Mac first (Apple Silicon, macOS 14.2 or later), then installs the same build as the
  Terminal command, checked against the release's signed checksums and the app's code signature,
  into Applications (or ~/Applications), and tells you the first-launch steps.

Open madal from Applications; an orange "m" shows in the menu bar. When a call starts it asks
"Record this call?". The first recording asks for the microphone (your side) and system audio
(the other side). Allow both once, and updates keep them. The first launch also downloads the
speech model, about 500 MB. After a meeting is published, madal can show a "Meeting ready to
summarize" notification with a Copy prompt button, if you allow notifications.

The app isn't notarized by Apple yet. If you download the `.dmg` from the releases page in a
browser, macOS blocks the first open: click Done, then System Settings › Privacy & Security ›
Open Anyway. The Terminal install and the agent install don't need that step.

---

<div align="center">

## Sharing with people and your org

</div>

Share by name and the link carries no key at all. Only the people you chose can open it, and a
forwarded link opens nothing.

```bash
madal publish plan.md --with alice@example.com,bob@example.com
madal publish plan.md --org                     # everyone in your org; --org acme if you're in several
madal share <link-or-id> --with bob@example.com # repeat --with, or give a comma list
madal share <link-or-id> --org
madal share <link-or-id> --remove bob@example.com
madal share <link-or-id> --remove org           # stop sharing with your org
madal share <link-or-id> --link                 # anyone with the full link
madal share <link-or-id> --restricted           # only the people you named: no link, no org
madal share <link-or-id> --with bob@example.com --role edit   # bob can publish new versions too
```

`--role` sets what people can do: `comment` (the default), `view`, or `edit`. An editor reads,
comments, and publishes and restores versions with `madal update` and `madal restore`. They can't
delete the page, share it, change roles or settings, or take it over. `edit` is for people named by
email on a private page, never for your org. Sharing again with `--role comment` or `view`, or
removing them, stops their updates at once. When a removal means the page needs a new key, only you
can publish the next version. An editor keeps the role if they leave your org, until you change it.

You can share with anyone's email. If they don't use Madal yet they're invited, and madal prints
an invite link for each person. Send each one their own link: it opens as soon as they sign up
with that email, even if your machine is off. The link carries a secret that only works for that
email's account, and the server never sees it.

Teams were removed. `madal team` now says so and stops; pages shared with a team before still
open for its members. Share with your org, or with people.

### Orgs

An org has its own key, and a page shared with it opens for every member. Every member is a seat
at $10 a month.

```bash
madal org create                                # the org for your email's domain: you@acme.com makes Acme, for acme.com
madal org join                                  # someone else at acme.com: waiting? (--cancel: not for work)
madal org requests                              # admins: who waits
madal org approve dan@acme.com                  # or --all; madal org decline dan@acme.com turns him down
madal org preapprove erin@acme.com,fay@acme.com # added as soon as they sign up and an admin's madal runs
madal org preapproved                           # the list; madal org preapprove --remove fay@acme.com
madal org admin add acme dan@acme.com           # asks you to confirm dan's fingerprint
madal org show acme                             # members, "3 seats x $10 = $30/month", plan, domain
madal org remove acme dan@acme.com              # rotates the org key
```

Joining takes an admin's approval, and nobody has to ask. Someone who signs in with a verified
email at the org's domain is listed for its admins, and keeps using madal on their own until an
admin approves. "Not for work" (`madal org join --cancel`, or the link in the browser) takes them
off the list. Before giving them the org key, the admin's madal checks that their
encryption key is signed by their own signing key, and refuses otherwise. An admin can approve
emails ahead of time; once such a person has an account, the next admin's madal to run adds them
and prints a line saying so. There are no org invite links: listing and pre-approval are the
only ways in.

Org admins can act as the owner of any page shared with the org. They can publish new versions, restore, delete and change who it's shared with, and
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
anyone after them at that domain is listed for its admins when they sign in, and an admin approves. Domains compare by their registrable part, so `eng.acme.co.uk` is `acme.co.uk`, and free
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

The first time you share with someone, madal shows their **key fingerprint**. Compare it with what
`madal whoami` shows them, over a channel you trust, to be sure the server handed you their real
key. If their key ever changes, madal stops and tells you the new fingerprint.

### Your account

`madal account delete` (or **Delete my account** on the keys page) deletes everything: what you
published, what you shared and what was shared with you, your place in an org, your
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
| **Orgs** | The key is wrapped to the org's key. Every change to the org key is signed by an admin and chained to the one before, and it's rotated when someone is removed |
| **Your keys** | Kept in a vault encrypted on your device with your master password (PBKDF2-SHA256, 600,000 iterations) and a 128-bit Secret Key that never leaves your devices, before it's stored on the server. A copy of the server's data can't be opened by guessing your password |
| **Viewing** | Artifacts render in a sandboxed frame on a separate domain, away from your session and keys |

Exact formats are on the [security page](https://madal.facets.cloud/security).

### What it can't protect against

- Anyone with a full link can read a link artifact. Use `--to` or a password for anything that
  might travel further than you intend.
- Public pages (`--public`) are plaintext by design, so links unfurl in chat apps.
- The viewer's JavaScript is served by the Madal server, which could in principle serve code that
  reads keys. Each release signs a list of every page and script the site serves, and
  `madal verify` checks the live site against it, so a change everyone gets shows up. It can't see
  code sent to one browser only; a verifier extension is planned for that.
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
