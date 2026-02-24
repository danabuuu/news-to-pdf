#!/bin/bash
# install.sh
# Sets up the Apple News → PDF keyboard shortcut on macOS.
#
# What this script does:
#   1. Installs Homebrew (if missing)
#   2. Installs skhd (hotkey daemon) via Homebrew
#   3. Copies the capture scripts to ~/.local/bin/
#   4. Merges the hotkey config into ~/.config/skhd/skhdrc
#   5. Starts skhd as a Login Item (runs at every startup)
#   6. Opens System Settings so you can grant Accessibility access
#
# Local install (after git clone):
#   chmod +x install.sh && ./install.sh
#
# One-liner remote install:
#   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/news-to-pdf/main/install.sh | bash

set -euo pipefail

# ── GitHub source (update YOUR_USERNAME after you publish the repo) ────────────
GITHUB_USER="danabuuu"
REPO_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/news-to-pdf/main"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
BIN_DIR="$HOME/.local/bin"
SKHD_CFG="$HOME/.config/skhd/skhdrc"
HOTKEY_MARKER="# Apple News → PDF"

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
success() { echo -e "${GREEN}[DONE]${RESET}  $*"; }
die()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ── Helper: copy from local clone OR download from GitHub ─────────────────────
fetch_file() {
    local filename="$1"
    local dest="$2"
    local local_src="$SCRIPT_DIR/$filename"

    if [[ -f "$local_src" ]]; then
        cp "$local_src" "$dest"
    else
        if [[ "$GITHUB_USER" == "YOUR_USERNAME" ]]; then
            die "Remote install requires GITHUB_USER to be set in this script."
        fi
        info "Downloading ${filename}…"
        curl -fsSL "${REPO_RAW}/${filename}" -o "$dest"
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Apple News → PDF  ·  Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Homebrew ────────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    info "Homebrew not found — installing…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    info "Homebrew already installed."
fi

# Make sure brew is on PATH (Apple Silicon default path)
if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ── 2. Install skhd ───────────────────────────────────────────────────────────
if ! brew list skhd &>/dev/null; then
    info "Installing skhd…"
    brew tap koekeishiya/formulae
    brew install koekeishiya/formulae/skhd
else
    info "skhd already installed."
fi

# ── 3. Copy scripts to ~/.local/bin/ ──────────────────────────────────────────
info "Installing capture scripts to ${BIN_DIR}…"
mkdir -p "$BIN_DIR"

fetch_file "news_to_pdf.sh" "$BIN_DIR/news_to_pdf.sh"
fetch_file "combine_pdf.py"  "$BIN_DIR/combine_pdf.py"
chmod +x "$BIN_DIR/news_to_pdf.sh"
chmod +x "$BIN_DIR/combine_pdf.py"

success "Scripts installed."

# ── 4. Merge hotkey config into ~/.config/skhd/skhdrc ─────────────────────────
info "Configuring skhd hotkey…"

# If ~/.config exists but is owned by root, reclaim it
if [[ -e "$HOME/.config" ]]; then
    config_owner=$(stat -f "%Su" "$HOME/.config" 2>/dev/null || stat -c "%U" "$HOME/.config" 2>/dev/null)
    if [[ "$config_owner" != "$(whoami)" ]]; then
        warn "~/.config is owned by '$config_owner' — reclaiming with sudo chown…"
        sudo chown -R "$(whoami)" "$HOME/.config" || die "Could not chown ~/.config. Try: sudo chown -R \$(whoami) ~/.config"
    fi
fi
mkdir -p "$HOME/.config/skhd"
chmod u+rwx "$HOME/.config" "$HOME/.config/skhd"
touch "$SKHD_CFG"

if grep -qF "$HOTKEY_MARKER" "$SKHD_CFG"; then
    warn "Hotkey already present in $SKHD_CFG — skipping."
else
    echo "" >> "$SKHD_CFG"
    SKHD_SNIPPET="$(mktemp /tmp/news_pdf_skhdrc_XXXXXX)"
    fetch_file "skhdrc" "$SKHD_SNIPPET"
    cat "$SKHD_SNIPPET" >> "$SKHD_CFG"
    rm -f "$SKHD_SNIPPET"
    success "Hotkey added to $SKHD_CFG"
fi

# ── 5. Start skhd as a Login Item (auto-starts at boot) ───────────────────────
info "Registering skhd as a startup service…"
# --start-service installs the launchd plist and starts skhd.
# If already installed, restart so any config changes take effect.
if launchctl list 2>/dev/null | grep -q "com.koekeishiya.skhd"; then
    info "skhd service already registered — restarting to pick up config changes…"
    skhd --stop-service 2>/dev/null || true
    sleep 1
fi
skhd --start-service
success "skhd started and will run at every login."

# ── 6. Create output directory ────────────────────────────────────────────────
mkdir -p "$HOME/Documents/News PDFs"
success "Output folder ready: ~/Documents/News PDFs/"

# ── 7. Permission prompts ──────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}  ACTION REQUIRED: Two Permissions Needed${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  skhd needs two permissions in System Settings."
echo "  For each one: click [+], navigate to"
echo "  /opt/homebrew/bin/ and select skhd."
echo ""
echo "  1) Accessibility  — to scroll Apple News"
echo "  2) Screen Recording — to take screenshots"
echo ""
echo "  We'll open System Settings twice, once for each."
echo ""
read -rp "  Press Enter to grant Accessibility access…"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
read -rp "  Press Enter to grant Screen Recording access…"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Installation complete!${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  HOW TO USE"
echo "  ──────────"
echo "  1. Open Apple News and navigate to an article."
echo "  2. Press  Cmd + Shift + P"
echo "  3. The screen will scroll automatically from top to"
echo "     bottom, taking screenshots as it goes."
echo "  4. A notification will appear when the PDF is ready."
echo "  5. The PDF opens automatically in Preview."
echo ""
echo "  WHERE ARE MY PDFS?"
echo "  ───────────────────"
echo "  ~/Documents/News PDFs/"
echo "  Files are named:  news_article_YYYYMMDD_HHMMSS.pdf"
echo ""
echo "  TIPS"
echo "  ────"
echo "  • The hotkey only fires inside Apple News — it won't"
echo "    interfere with Cmd+Shift+P in other apps."
echo "  • Very long articles are capped at 60 pages."
echo "  • If capture looks cut off, make sure the News window"
echo "    is fully visible (not partially behind another window)."
echo ""
echo "  TROUBLESHOOTING"
echo "  ───────────────"
echo "  • Nothing happens?  Check System Settings → Privacy &"
echo "    Security → Accessibility — skhd must be toggled ON."
echo "  • PDF creation failed?  Check /tmp/news_pdf.log"
echo "  • Hotkey stopped working after reboot?"
echo "    Run:  skhd --start-service"
echo ""
echo "  MORE INFO"
echo "  ─────────"
echo "  https://github.com/danabuuu/news-to-pdf"
echo ""
