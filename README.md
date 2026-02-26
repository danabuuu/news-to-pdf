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

You must grant `skhd` two permissions — the installer opens System Settings for each automatically. If you missed either:

| Permission | Where to add it |
|---|---|
| **Accessibility** | System Settings → Privacy & Security → Accessibility → [+] → `/opt/homebrew/bin/skhd` |
| **Screen Recording** | System Settings → Privacy & Security → Screen Recording → [+] → `/opt/homebrew/bin/skhd` |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Nothing happens when pressing Cmd+Shift+P | Check Accessibility access is toggled ON for skhd |
| Screenshots are black / PDF is blank | Check Screen Recording access is toggled ON for skhd |
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

If you installed from a local clone:

```bash
./uninstall.sh
```

Or run the uninstaller directly without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/danabuuu/news-to-pdf/main/uninstall.sh | bash
```

This stops and removes the skhd service, uninstalls skhd via Homebrew, removes the capture scripts from `~/.local/bin/`, and strips the hotkey block from `~/.config/skhd/skhdrc`. Your saved PDFs in `~/Documents/News PDFs/` are not touched.
