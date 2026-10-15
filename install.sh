#!/bin/sh
# Install the pinned PCB-layout toolchain (Java 17 + Freerouting 1.9.0) on Linux/macOS from
# official upstream releases, verified against toolchain.lock. Writes tools.json for the kit.
#
#   sh install.sh [--dest DIR] [--kicad]
#
# --dest   install folder (default: $CZL_TOOLS, else ~/.cuzor-tools)
# --kicad  macOS: also download + verify the pinned KiCad .dmg (you drag it to Applications).
#          Linux: KiCad comes from the official PPA (printed below); nothing is installed here.
set -eu

DEST="${CZL_TOOLS:-$HOME/.cuzor-tools}"
WANT_KICAD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --kicad) WANT_KICAD=1; shift ;;
    *) echo "unknown option $1"; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK="$HERE/toolchain.lock"
PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "python3 is needed to read toolchain.lock"; exit 1; }
lock() { "$PY" -c "import json,sys;d=json.load(open('$LOCK'));v=d
for k in sys.argv[1].split('.'): v=v[k]
print(v)" "$1"; }

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) JKEY=linux-x64 ;;
  Darwin-x86_64) JKEY=macos-x64 ;;
  Darwin-arm64) JKEY=macos-arm64 ;;
  *) echo "unsupported platform $(uname -s)-$(uname -m)"; exit 1 ;;
esac

mkdir -p "$DEST/downloads"
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
get() {  # get <lock path> -> prints local file
  f="$DEST/downloads/$(lock "$1.file")"; want="$(lock "$1.sha256")"
  if [ -f "$f" ] && [ "$(sha "$f")" = "$want" ]; then echo "$f"; return; fi
  echo "download $(lock "$1.url")" >&2
  curl -fsSL -o "$f" "$(lock "$1.url")"
  got="$(sha "$f")"
  if [ "$got" != "$want" ]; then rm -f "$f"; echo "SHA-256 mismatch for $f: $got != $want" >&2; exit 1; fi
  echo "  sha256 ok" >&2
  echo "$f"
}

JRE_TGZ="$(get "java.$JKEY")"
if [ ! -x "$DEST/jre17/bin/java" ] && [ ! -x "$DEST/jre17/Contents/Home/bin/java" ]; then
  rm -rf "$DEST/jre17" "$DEST/jre_extract"; mkdir -p "$DEST/jre_extract"
  tar -xzf "$JRE_TGZ" -C "$DEST/jre_extract"
  mv "$DEST/jre_extract"/* "$DEST/jre17"; rm -rf "$DEST/jre_extract"
fi
JAVA="$DEST/jre17/bin/java"; [ -x "$JAVA" ] || JAVA="$DEST/jre17/Contents/Home/bin/java"

JAR_SRC="$(get freerouting)"
JAR="$DEST/$(lock freerouting.file)"
cp "$JAR_SRC" "$JAR"

CLI="$(command -v kicad-cli || true)"
[ -z "$CLI" ] && [ -x /Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli ] && CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
if [ -z "$CLI" ] && [ "$WANT_KICAD" = 1 ]; then
  case "$JKEY" in
    macos-*) DMG="$(get kicad.macos)"; echo "verified $DMG - open it and drag KiCad to Applications, then rerun"; ;;
    linux-*) echo "$(lock kicad.linux)" ;;
  esac
fi
KVER=""; [ -n "$CLI" ] && KVER="$("$CLI" version | tr -d '\r')"

"$PY" - "$DEST" "$(lock id)" "$JAVA" "$JAR" "$CLI" "$KVER" <<'EOF'
import json, sys
d, tid, java, jar, cli, kver = sys.argv[1:7]
json.dump({'toolchain': tid, 'java': java, 'freerouting_jar': jar, 'kicad_cli': cli or None,
           'kicad_version': kver or None}, open(d + '/tools.json', 'w'), indent=2)
EOF

echo
echo "toolchain $(lock id) -> $DEST"
echo "  java        $JAVA"
echo "  freerouting $JAR"
ACC="$(lock kicad.accept_prefix)"
case "$KVER" in
  "$ACC"*) echo "  kicad       $KVER ($CLI)"; echo OK ;;
  "") echo "  kicad       NOT FOUND - install KiCad $(lock kicad.version) (see --kicad)"; exit 2 ;;
  *) echo "  kicad       $KVER - need $ACC.x"; exit 2 ;;
esac
