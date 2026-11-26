---
description: Install the madal CLI, its agent skill and, on a Mac that can run it, the madal Meetings app
---

The user ran this command to install madal on this machine. Do it now, without asking again.

1. On macOS or Linux, run:

   ```sh
   curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --all
   ```

   It installs the `madal` binary into `~/.local/bin` (checked against the release's checksums),
   writes the madal skill into each agent's skills folder, and on a Mac with Apple Silicon and
   macOS 14.2 or later installs madal.app into Applications. On other machines it says why it
   skipped the app and installs the rest.

   On Windows, or if `curl` isn't there, run `npm install -g @facets-cloud/madal` and then
   `madal skills install`. The Meetings app is Mac only.

2. Tell the user what it printed, in a few lines: where `madal` went, and the PATH line if it
   printed one.
3. If it installed the app, tell the user to open madal from Applications and to allow the
   microphone and system audio when macOS asks. Only they can click those.
4. Tell them to run `madal login` in a terminal, or to ask you to sign in, which runs the same
   command.

Run nothing else. If the install fails, show the user the error and stop.
