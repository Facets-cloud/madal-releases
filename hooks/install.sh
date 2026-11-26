#!/bin/sh
# Install madal from the latest GitHub release.
#
#   curl -fsSL https://madal.facets.cloud/install.sh | sh
#
# It downloads the archive for this OS and CPU, checks its SHA-256 against the
# release's checksums.txt, and installs the binary into $MADAL_INSTALL_DIR
# (default ~/.local/bin). Set MADAL_VERSION=v0.1.1 to pin a version.
#
#   curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --app
#
# installs the madal Meetings app instead (macOS 14.2 or later on Apple Silicon): it downloads
# madal-Meetings-<version>.zip, checks it against its .sha256 file from the same release, and
# puts madal.app in $MADAL_APP_DIR (default /Applications when writable, else ~/Applications).
# A download with curl isn't quarantined, so macOS opens the app without asking for Open Anyway.
#
#   curl -fsSL https://madal.facets.cloud/install.sh | sh -s -- --all
#
# installs everything in one go: the binary, the agent skill (madal skills install, into each
# agent found under your home) and, on a Mac that can run it, the madal Meetings app. On any
# other machine it says why it skipped the app and installs the rest.
set -eu

cli=1
app=0
skill=0
for arg in "$@"; do
  case "$arg" in
    --app) cli=0 app=1 ;;
    --all) cli=1 app=1 skill=1 ;;
    *) echo "madal install: unknown option $arg" >&2; exit 1 ;;
  esac
done

repo="Facets-cloud/madal-releases"
dir="${MADAL_INSTALL_DIR:-$HOME/.local/bin}"

fail() { echo "madal install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "needs $1"; }
need curl
need tar
need uname

# One of GitHub's download addresses doesn't answer from some networks, and
# curl waits over a minute on it before trying the next. A short connect
# timeout makes it move on in a second or two.
dl() { curl -fL --connect-timeout 4 --retry 2 "$@"; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported OS $(uname -s); on Windows, download the zip from https://github.com/$repo/releases" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) fail "unsupported CPU $(uname -m)" ;;
esac

# Why this machine can't run the madal app, or nothing when it can.
app_unsupported() {
  [ "$os/$arch" = darwin/arm64 ] || { echo "the madal app needs a Mac with Apple Silicon"; return; }
  # 14.2 is the first macOS with the system audio capture the app records calls with.
  macos=$(sw_vers -productVersion 2>/dev/null || true)
  major=${macos%%.*}
  minor=0
  case "$macos" in *.*) minor=${macos#*.}; minor=${minor%%.*} ;; esac
  case "$major.${minor:-0}" in
    *[!0-9.]* | .*) echo "couldn't read the macOS version (sw_vers -productVersion said '$macos')"; return ;;
  esac
  if [ "$major" -lt 14 ] || { [ "$major" -eq 14 ] && [ "${minor:-0}" -lt 2 ]; }; then
    echo "the madal app needs macOS 14.2 or later; this Mac runs macOS $macos. Update macOS in System Settings > General > Software Update."
  fi
}

if [ "$app" = 1 ]; then
  why=$(app_unsupported)
  if [ -n "$why" ]; then
    [ "$cli" = 1 ] || fail "$why"
    echo "Skipping the madal app: $why"
    app=0
  fi
fi

version="${MADAL_VERSION:-}"
if [ -z "$version" ]; then
  version=$(dl -sS "https://api.github.com/repos/$repo/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$version" ] || fail "couldn't find the latest release"
fi

base="https://github.com/$repo/releases/download/$version"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

install_app() {
  need ditto
  zip="madal-Meetings-${version#v}.zip"
  echo "Downloading the madal app $version"
  dl --progress-bar -o "$tmp/$zip" "$base/$zip"
  dl -sS -o "$tmp/$zip.sha256" "$base/$zip.sha256"
  want=$(cut -d' ' -f1 "$tmp/$zip.sha256")
  [ -n "$want" ] || fail "no checksum in $zip.sha256"
  [ "$(sha256 "$tmp/$zip")" = "$want" ] || fail "checksum mismatch for $zip; not installing"
  echo "Checksum verified"
  ditto -x -k "$tmp/$zip" "$tmp/app"
  [ -d "$tmp/app/madal.app" ] || fail "$zip has no madal.app"
  dest="${MADAL_APP_DIR:-}"
  if [ -z "$dest" ]; then
    if [ -w /Applications ]; then dest=/Applications; else dest="$HOME/Applications"; fi
  fi
  mkdir -p "$dest"
  # Replace the whole bundle so no file from an older version stays behind.
  rm -rf "${dest:?}/madal.app"
  ditto "$tmp/app/madal.app" "$dest/madal.app"
  echo "Installed $dest/madal.app"
  echo "If madal was running, quit it from its menu and open it again."
  echo "Next: open \"$dest/madal.app\", then allow the microphone and system audio when macOS asks."
}

if [ "$cli" = 0 ]; then
  install_app
  exit 0
fi

name="madal_${version#v}_${os}_${arch}"

echo "Downloading madal $version for $os/$arch"
dl --progress-bar -o "$tmp/$name.tar.gz" "$base/$name.tar.gz"
echo "Downloading checksums"
dl -sS -o "$tmp/checksums.txt" "$base/checksums.txt"

want=$(grep " $name.tar.gz\$" "$tmp/checksums.txt" | cut -d' ' -f1)
[ -n "$want" ] || fail "no checksum listed for $name.tar.gz"
[ "$(sha256 "$tmp/$name.tar.gz")" = "$want" ] || fail "checksum mismatch for $name.tar.gz; not installing"
echo "Checksum verified"

tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
mkdir -p "$dir"
install -m 0755 "$tmp/$name/madal" "$dir/madal"
echo "Installed $dir/madal"

case ":$PATH:" in
  *":$dir:"*) ;;
  *) echo "Add $dir to your PATH, for example: export PATH=\"$dir:\$PATH\"" ;;
esac

if [ "$skill" = 1 ]; then
  # The binary carries the skill; this writes it into each agent's skills folder.
  "$dir/madal" skills install
fi
if [ "$app" = 1 ]; then
  install_app
fi
echo "Next: madal login"
