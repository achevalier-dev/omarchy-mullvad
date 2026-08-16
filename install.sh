#!/bin/bash
# Installs the mullvad-menu helper and the Omarchy menu rows.
# Safe to re-run: the menu block is replaced in place, never duplicated.

set -euo pipefail

NAME="omarchy-mullvad"
SCRIPT="mullvad-menu"
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$HOME/.local/bin"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

command -v mullvad >/dev/null || echo "warning: the mullvad CLI is not on PATH" >&2

mkdir -p "$BIN_DIR"
ln -sf "$REPO/bin/$SCRIPT" "$BIN_DIR/$SCRIPT"
echo "linked $BIN_DIR/$SCRIPT -> $REPO/bin/$SCRIPT"

mkdir -p "$(dirname "$MENU")"
[[ -f $MENU ]] || printf '{\n}\n' >"$MENU"
cp "$MENU" "$MENU.bak.$(date +%s)"

python3 - "$REPO/extensions/mullvad.jsonc" "$MENU" "$NAME" <<'PY'
import pathlib, re, sys

snippet = pathlib.Path(sys.argv[1]).read_text().rstrip()
target = pathlib.Path(sys.argv[2])
name = sys.argv[3]

begin, end = f"  // >>> {name}", f"  // <<< {name}"
block = f"{begin}\n{snippet}\n{end}\n"
text = target.read_text()

if begin in text and end in text:
    text = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", lambda m: block, text, flags=re.S)
else:
    cut = text.rstrip().rfind("}")
    head = text.rstrip()[:cut].rstrip()
    # JSONC tolerates a trailing comma but not a missing one. The comma belongs
    # on the last entry, which is not the last line when a block ends in a
    # comment — putting it there would comment the comma out.
    lines = head.splitlines()
    for i in range(len(lines) - 1, -1, -1):
        stripped = lines[i].strip()
        if not stripped or stripped.startswith("//"):
            continue
        if not stripped.endswith(",") and not stripped.endswith("{"):
            lines[i] = lines[i].rstrip() + ","
        break
    head = "\n".join(lines)
    text = head + "\n" + block + "}\n"

target.write_text(text)
PY

echo "menu rows installed in $MENU (previous version backed up alongside it)"
omarchy menu refresh >/dev/null 2>&1 || true

cat <<'NOTE'

The bar widget is a separate, optional piece:

    omarchy plugin add https://github.com/achevalier-dev/omarchy-mullvad.git --enable

NOTE
