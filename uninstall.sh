#!/bin/bash
# uninstall.sh
# Removes everything that install.sh put in place so you can do a clean re-install.
#
# What this script removes:
#   • Stops and unregisters the skhd launchd service
#   • Uninstalls skhd via Homebrew
#   • Removes news_to_pdf.sh and combine_pdf.py from ~/.local/bin/
#   • Strips the Apple News → PDF hotkey block from ~/.config/skhd/skhdrc
#
# What it does NOT touch:
#   • Homebrew itself
#   • ~/Documents/News PDFs/  (your saved PDFs are left intact)
#
# Usage:
#   chmod +x uninstall.sh && ./uninstall.sh

set -euo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "[ERROR] Do not run this script with sudo." >&2
    echo "        Run it as your normal user:  ./uninstall.sh" >&2
    exit 1
fi

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RESET="\033[0m"

info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
success() { echo -e "${GREEN}[DONE]${RESET}  $*"; }

# Make brew available if it exists
if   [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew    ]]; then eval "$(/usr/local/bin/brew shellenv)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Apple News → PDF  ·  Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Stop skhd service ───────────────────────────────────────────────────────
if launchctl list 2>/dev/null | grep -q "com.koekeishiya.skhd"; then
    info "Stopping skhd service…"
    skhd --stop-service 2>/dev/null || true
    success "skhd service stopped."
else
    info "skhd service not running — skipping."
fi

# ── 2. Uninstall skhd ─────────────────────────────────────────────────────────
if command -v brew &>/dev/null && brew list skhd &>/dev/null 2>&1; then
    info "Uninstalling skhd via Homebrew…"
    brew uninstall skhd
    success "skhd uninstalled."
else
    info "skhd not installed via Homebrew — skipping."
fi

# ── 3. Remove scripts from ~/.local/bin/ ──────────────────────────────────────
for f in news_to_pdf.sh combine_pdf.py; do
    target="$HOME/.local/bin/$f"
    if [[ -f "$target" ]]; then
        info "Removing $target…"
        rm -f "$target"
        success "Removed $f"
    else
        info "$f not found in ~/.local/bin/ — skipping."
    fi
done

# ── 4. Strip the hotkey block from ~/.config/skhd/skhdrc ─────────────────────
SKHD_CFG="$HOME/.config/skhd/skhdrc"
HOTKEY_MARKER="# Apple News → PDF"

if [[ -f "$SKHD_CFG" ]] && grep -qF "$HOTKEY_MARKER" "$SKHD_CFG"; then
    info "Removing hotkey block from $SKHD_CFG…"
    # Use Python to delete from the marker line through the closing ']' of the block
    python3 - "$SKHD_CFG" <<'PYEOF'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Remove: optional blank line before marker, the marker, through the closing ]
cleaned = re.sub(
    r'\n?# Apple News → PDF\n.*?^\]\n?',
    '',
    text,
    flags=re.DOTALL | re.MULTILINE
)
open(path, 'w').write(cleaned)
PYEOF
    success "Hotkey block removed from skhdrc."
else
    info "Hotkey block not found in skhdrc — skipping."
fi

# ── 5. Remove skhd config dir if it is now empty ──────────────────────────────
if [[ -d "$HOME/.config/skhd" ]]; then
    if [[ -z "$(find "$HOME/.config/skhd" -mindepth 1 -maxdepth 1)" ]]; then
        rmdir "$HOME/.config/skhd"
        info "Removed empty ~/.config/skhd/"
    else
        info "~/.config/skhd/ has other content — leaving it in place."
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Uninstall complete!${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Your saved PDFs in ~/Documents/News PDFs/ were NOT removed."
echo ""
echo "  To re-install, run:  ./install.sh"
echo ""
