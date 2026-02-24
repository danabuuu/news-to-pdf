#!/bin/bash
# news_to_pdf.sh
# Captures the frontmost Apple News article by scrolling and screenshotting,
# then stitches all frames into a PDF saved to ~/Documents/News PDFs/
#
# Dependencies: skhd (hotkey trigger), Python 3 (bundled with macOS)
# Triggered by: Cmd+Shift+P while Apple News is frontmost

SAVE_DIR="$HOME/Documents/News PDFs"
SCRIPT_DIR="$(dirname "$0")"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_DIR=$(mktemp -d /tmp/news_pdf_XXXXXX)
OUTPUT="$SAVE_DIR/news_article_$TIMESTAMP.pdf"

mkdir -p "$SAVE_DIR"

# ── 1. Verify Apple News is frontmost ─────────────────────────────────────────
APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)

if [ "$APP" != "News" ]; then
    osascript -e 'display notification "Open Apple News and focus an article first." with title "News → PDF" subtitle "Wrong app"'
    rm -rf "$TEMP_DIR"
    exit 1
fi

# ── 2. Get the Apple News window bounds (in logical/point coordinates) ─────────
read -r X Y W H < <(osascript << 'APPLESCRIPT'
tell application "System Events"
    tell process "News"
        set w to first window
        set p to position of w
        set s to size of w
        set x1 to item 1 of p
        set y1 to item 2 of p
        set w1 to item 1 of s
        set h1 to item 2 of s
        return (x1 as string) & " " & (y1 as string) & " " & (w1 as string) & " " & (h1 as string)
    end tell
end tell
APPLESCRIPT
)

if [ -z "$X" ] || [ -z "$W" ]; then
    osascript -e 'display notification "Could not read Apple News window bounds." with title "News → PDF"'
    rm -rf "$TEMP_DIR"
    exit 1
fi

# ── 3. Scroll to the very top of the article ──────────────────────────────────
osascript -e 'tell application "System Events" to key code 115' # Fn+Left / Home
sleep 0.6

osascript -e 'display notification "Capturing article — please wait…" with title "News → PDF"'

# ── 4. Scroll-and-capture loop ─────────────────────────────────────────────────
# Strategy: capture full window frame after each Page-Down.
# Stop when two consecutive frames are identical (reached the bottom).
FRAME=0
PREV_HASH=""
MAX_FRAMES=60   # safety cap (~60 page-downs is a very long article)

while [ $FRAME -lt $MAX_FRAMES ]; do
    SCREENSHOT="$TEMP_DIR/frame_$(printf '%04d' $FRAME).png"

    # -x = no sound, -R = region x,y,w,h
    screencapture -x -R "${X},${Y},${W},${H}" "$SCREENSHOT"

    HASH=$(md5 -q "$SCREENSHOT" 2>/dev/null || md5sum "$SCREENSHOT" | cut -d' ' -f1)

    if [ "$HASH" = "$PREV_HASH" ] && [ $FRAME -gt 0 ]; then
        # Bottom of article reached — discard duplicate
        rm -f "$SCREENSHOT"
        break
    fi

    PREV_HASH="$HASH"
    FRAME=$((FRAME + 1))

    # Page Down — scrolls one screen-height in Apple News
    osascript -e 'tell application "System Events" to key code 121'   # Page Down
    sleep 0.45   # wait for scroll animation + content render
done

TOTAL_FRAMES=$FRAME

if [ "$TOTAL_FRAMES" -eq 0 ]; then
    osascript -e 'display notification "No frames captured." with title "News → PDF"'
    rm -rf "$TEMP_DIR"
    exit 1
fi

# ── 5. Combine screenshots into a PDF ─────────────────────────────────────────
python3 "$SCRIPT_DIR/combine_pdf.py" "$TEMP_DIR" "$OUTPUT"
EXIT_CODE=$?

# ── 6. Cleanup temp files ─────────────────────────────────────────────────────
rm -rf "$TEMP_DIR"

# ── 7. Notify and open ────────────────────────────────────────────────────────
if [ $EXIT_CODE -eq 0 ] && [ -f "$OUTPUT" ]; then
    FILENAME=$(basename "$OUTPUT")
    osascript -e "display notification \"Saved: $FILENAME\" with title \"News → PDF ✓\" subtitle \"$TOTAL_FRAMES frames captured\""
    open "$OUTPUT"
else
    osascript -e 'display notification "PDF creation failed. Check /tmp/news_pdf.log for details." with title "News → PDF ✗"'
    exit 1
fi
