#!/bin/sh
# madal plugin hook: says when a madal meeting is ready to summarize, or replies
# wait on a comment thread the session asked on (hook input on stdin). Claude
# Code runs it at SessionStart and UserPromptSubmit, Gemini CLI at
# SessionStart, with the event as $1. It finds the madal profile as the madal
# CLI does and runs the hook script the madal MCP server keeps in that
# profile's folder (meetings-hook.sh), so the text lives in one place. It reads
# local files only: no network, no madal process. Any miss stays silent.
event=$1
if [ -n "$CLAUDE_PLUGIN_ROOT" ]; then
  agent=claude-code
  settings=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json
else
  agent=gemini
  settings=$HOME/.gemini/settings.json
fi
# `madal mcp install` writes the same hook into the agent's own settings. When
# that one is there it runs instead, so a session gets one notice, not two.
grep -qs madal-meetings-hook "$settings" && exit 0
if [ -n "$MADAL_HOME" ]; then
  base=$MADAL_HOME
elif [ "$(uname -s)" = Darwin ]; then
  base="$HOME/Library/Application Support/madal"
else
  base="${XDG_CONFIG_HOME:-$HOME/.config}/madal"
fi
profile=$MADAL_PROFILE
if [ -z "$profile" ] && [ -f "$base/profiles.json" ]; then
  profile=$(sed -n 's/.*"default"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$base/profiles.json" | head -n 1)
fi
case $profile in
'' | default) dir=$base ;;
[a-z0-9]*) case $profile in *[!a-z0-9_-]*) exit 0 ;; esac; dir="$base/profiles/$profile" ;;
*) exit 0 ;;
esac
[ -f "$dir/meetings-hook.sh" ] || exit 0
exec sh "$dir/meetings-hook.sh" "$event" "$agent"
