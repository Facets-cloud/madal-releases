#!/bin/sh
# madal plugin setup. Claude Code runs it in the background when a session
# starts; bin/madal runs it with `cli` when madal isn't installed yet, and with
# `path` to learn where the binary goes.
#
# It installs the madal binary with the installer beside it, which checks the
# release's checksums: install.sh into $MADAL_INSTALL_DIR (default
# ~/.local/bin), or on Windows (Git Bash, which Claude Code's Bash tool runs)
# install.ps1 into %LOCALAPPDATA%\Programs\madal. The release is the plugin's
# own (v0.11.0), so no GitHub API lookup is needed; madal updates itself
# from there. Without `cli` it then installs the madal Meetings app on a Mac
# that can run it, once (a marker in the plugin's data folder keeps a deleted
# app deleted), and runs `madal session-start`, which keeps the meetings hook
# script current. Anything that fails stays quiet: the hook must never get in
# the session's way.
mode=${1:-session}
here=$(cd "$(dirname "$0")" && pwd)
export MADAL_VERSION="${MADAL_VERSION:-v0.11.0}"

case ${MADAL_PLUGIN_OS:-$(uname -s)} in
  MINGW* | MSYS* | CYGWIN*) windows=1 ;;
  *) windows= ;;
esac
if [ -n "$windows" ]; then
  if [ -n "${MADAL_INSTALL_DIR:-}" ]; then dir=$MADAL_INSTALL_DIR
  else dir="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")/Programs/madal"; fi
  bin=$dir/madal.exe
else
  dir=${MADAL_INSTALL_DIR:-$HOME/.local/bin}
  bin=$dir/madal
fi
[ "$mode" = path ] && { echo "$bin"; exit 0; }

if [ ! -x "$bin" ]; then
  if [ -n "$windows" ]; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here/install.ps1" || exit 1
  else
    sh "$here/install.sh" || exit 1
  fi
fi
[ "$mode" = cli ] && exit 0

marker="${CLAUDE_PLUGIN_DATA:-$HOME/.madal-plugin}/app-installed"
if [ "$(uname -s)" = Darwin ] && [ ! -e "$marker" ] &&
  [ ! -d /Applications/madal.app ] && [ ! -d "$HOME/Applications/madal.app" ]; then
  # install.sh --app fails on a Mac that can't run the app; that's fine.
  sh "$here/install.sh" --app >/dev/null 2>&1
  mkdir -p "$(dirname "$marker")" && : >"$marker"
fi

"$bin" session-start >/dev/null 2>&1
exit 0
