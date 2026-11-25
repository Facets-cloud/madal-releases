# Install madal for Mac

madal for Mac records your calls, writes the transcript on your Mac, and saves it to madal as an
encrypted page that only you can read until you share it. It needs a Mac with Apple Silicon and
macOS 14.2 or later.

## Install

Download
[madal-Meetings.dmg](https://github.com/Facets-cloud/madal-releases/releases/latest/download/madal-Meetings.dmg),
open it and drag madal into Applications. The first open needs Open Anyway (step 2 below).

Or in Terminal:

```sh
curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --app
```

It checks the download and puts madal in Applications. On a Mac older than macOS 14.2 it stops
and says so.

`--all` in place of `--app` also installs the `madal` command line tool and its agent skill.

Or ask your agent: "install madal for Mac". madal's `install_app` tool checks the Mac, installs
the same checked build as the Terminal command into Applications (or ~/Applications), and tells
you the steps below. It runs only when you ask.

## First launch

1. Open madal from Applications. An orange "m" appears in the menu bar. madal has no Dock icon.
   The first time, it opens a short setup list: microphone, system audio, notifications, your
   agent and the speech model, each with its state and a button. You can come back to it from
   Settings › Setup. macOS also says madal was added to Login Items, so it opens when you log in.
2. If you downloaded it in a browser, macOS says it can't check madal for malicious software.
   Click **Done**, open System Settings › Privacy & Security, scroll down to "madal was blocked",
   click **Open Anyway** and confirm with your password. You do this once per download. The
   Terminal install and the agent install skip this step.
3. Join a call. madal asks "Record this call?". Click **Record**.
4. macOS asks to let madal use the **microphone**. Click **Allow**. This records your side, as You.
5. macOS asks to let madal record **system audio**. Click **Allow**. This records the other side,
   as Them.
6. The first time, madal downloads its speech model (about 500 MB). The menu bar shows the
   progress. Until it's done, madal uses Apple's speech recognition on macOS 26 and later.
7. Optional: notifications. madal uses them to say "Meeting ready to summarize" after a meeting
   is published, with a **Copy prompt** button for your agent, and, if you set an app to Always
   record, to say it started recording, with a Stop button.

Updates keep both permissions, so you allow them once.

If you clicked Don't Allow, turn madal on in System Settings › Privacy & Security › Microphone,
and under Screen & System Audio Recording › System Audio Recording Only. Then stop and start the
recording again.

madal never asks for Screen Recording, Accessibility or your calendar. Audio stays on your Mac;
only the transcript goes to madal, encrypted. madal deletes a call's audio as soon as it is
transcribed. If transcription fails, the audio stays for Retry, and Settings › Kept audio lists it
with its size and a Delete button.

## Updates

madal updates itself. It checks at launch and every six hours, and installs a new version only
when nothing is recording or transcribing, then restarts. It checks the download against the
release's signed checksums and that the new app is signed by the same certificate, so your
permissions carry over. Settings shows the version, **Check now** and an **Automatic updates**
switch. If madal can't write the folder it's in, Settings says "update ready: install" and shows
the install command above, which also updates.

## Open at login and Quit

Turn **Open at login** off in Settings, or in System Settings › General › Login Items. Quit asks
first: while madal isn't running it won't offer to record your calls.
