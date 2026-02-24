# Apple News → PDF

Save any Apple News article as a PDF with a single keyboard shortcut.

Press **Cmd+Shift+P** while reading an article in Apple News — the screen scrolls automatically from top to bottom, captures every frame, and stitches them into a PDF saved to your Mac.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/danabuuu/news-to-pdf/main/install.sh | bash
```

That's it. No Python packages, no Node, no Xcode.

**Requirements:** macOS 12+, an internet connection for the one-time install.

---

## How to use

1. Open **Apple News** and navigate to an article.
2. Press **Cmd + Shift + P**.
3. A notification says *"Capturing article — please wait…"* while the page scrolls.
4. When done, the PDF opens automatically in Preview.

PDFs are saved to:

```
~/Documents/News PDFs/news_article_YYYYMMDD_HHMMSS.pdf
```

---

## After installing

You must grant **Accessibility access** to `skhd` once — the installer opens System Settings automatically at the end. If you missed it:

> **System Settings → Privacy & Security → Accessibility → [+] → /opt/homebrew/bin/skhd**

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens when pressing Cmd+Shift+P | Check Accessibility access is toggled ON for skhd |
| "Could not read Apple News window bounds" | Make sure an article is open and the News window is in front |
| "PDF creation failed" | Check `/tmp/news_pdf.log` for details |
| Hotkey stopped working after reboot | Run `skhd --start-service` in Terminal |

---

## How it works

- **[skhd](https://github.com/koekeishiya/skhd)** listens for the hotkey, scoped only to Apple News so it never conflicts with other apps.
- **`news_to_pdf.sh`** reads the News window bounds, scrolls to the top, then repeatedly takes a screenshot and presses Page Down until two consecutive frames are identical (end of article).
- **`combine_pdf.py`** converts the PNG frames to JPEG via `sips` (built-in to macOS) and builds a multi-page PDF in pure Python — no pip installs needed.

---

## Uninstall

```bash
rm ~/.local/bin/news_to_pdf.sh ~/.local/bin/combine_pdf.py
skhd --stop-service
# Remove the hotkey block from ~/.config/skhd/skhdrc
```
