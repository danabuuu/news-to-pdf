#!/usr/bin/env python3
"""
combine_pdf.py
Combines a directory of sequentially-named PNG screenshots into a single PDF.

Uses macOS-native PDFKit (via PyObjC) so no pip packages are needed.
Falls back to a sips-based approach if PyObjC is unavailable.

Usage:
    python3 combine_pdf.py <image_dir> <output.pdf>
"""
from __future__ import annotations

import sys
import os
import glob
import subprocess
import logging

logging.basicConfig(
    filename="/tmp/news_pdf.log",
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)


# ── Approach 1: macOS PDFKit via PyObjC (preferred, no extra installs) ─────────
def combine_via_pdfkit(png_files: list[str], output_path: str) -> bool:
    """
    Convert each PNG to a single-page PDF in memory using PDFKit,
    then concatenate all pages into one document.
    """
    try:
        import objc  # noqa: F401 — confirms PyObjC is available
        from Foundation import NSURL, NSData
        import Quartz  # PDFKit lives here in PyObjC

        master = Quartz.PDFDocument.alloc().init()

        for png_path in png_files:
            url = NSURL.fileURLWithPath_(png_path)
            # Create a CGImageSource → PDFPage
            src = Quartz.CGImageSourceCreateWithURL(url, None)
            if src is None:
                log.warning("Could not load image: %s", png_path)
                continue

            cg_image = Quartz.CGImageSourceCreateImageAtIndex(src, 0, None)
            if cg_image is None:
                log.warning("Could not decode image: %s", png_path)
                continue

            # Build a single-page PDFDocument from a temp in-memory PDF
            img_width  = Quartz.CGImageGetWidth(cg_image)
            img_height = Quartz.CGImageGetHeight(cg_image)
            page_rect  = Quartz.CGRectMake(0, 0, img_width, img_height)

            tmp_pdf_path = png_path.replace(".png", "_tmp.pdf")
            ctx = Quartz.CGPDFContextCreateWithURL(
                NSURL.fileURLWithPath_(tmp_pdf_path),
                page_rect,
                None,
            )
            if ctx is None:
                log.warning("Could not create PDF context for: %s", png_path)
                continue

            Quartz.CGContextBeginPage(ctx, page_rect)
            Quartz.CGContextDrawImage(ctx, page_rect, cg_image)
            Quartz.CGContextEndPage(ctx)
            del ctx  # flushes/closes the CGContext

            page_url = NSURL.fileURLWithPath_(tmp_pdf_path)
            page_doc = Quartz.PDFDocument.alloc().initWithURL_(page_url)
            if page_doc and page_doc.pageCount() > 0:
                master.insertPage_atIndex_(
                    page_doc.pageAtIndex_(0), master.pageCount()
                )

            os.remove(tmp_pdf_path)

        if master.pageCount() == 0:
            log.error("PDFKit: no pages assembled")
            return False

        out_url = NSURL.fileURLWithPath_(output_path)
        ok = master.writeToURL_(out_url)
        log.info("PDFKit wrote %d pages → %s (ok=%s)", master.pageCount(), output_path, ok)
        return bool(ok)

    except Exception as exc:
        log.warning("PDFKit approach failed: %s", exc)
        return False


# ── Approach 2: sips + pure-Python PDF builder (zero dependencies) ─────────────
def combine_via_sips(png_files: list[str], output_path: str) -> bool:
    """
    Convert each PNG to JPEG with sips (built-in macOS), then embed all
    JPEGs into a multi-page PDF built entirely in pure Python.
    No third-party packages required.
    """
    try:
        pages: list[tuple[bytes, int, int]] = []  # (jpeg_bytes, width, height)

        for png_path in png_files:
            jpg_path = png_path.replace(".png", "_tmp.jpg")
            result = subprocess.run(
                ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "85",
                 png_path, "--out", jpg_path],
                capture_output=True,
            )
            if result.returncode != 0 or not os.path.exists(jpg_path):
                log.warning("sips failed for %s: %s", png_path, result.stderr)
                continue
            with open(jpg_path, "rb") as f:
                jpeg_data = f.read()
            os.remove(jpg_path)
            w, h = _jpeg_dimensions(jpeg_data)
            pages.append((jpeg_data, w, h))

        if not pages:
            log.error("sips: no pages converted")
            return False

        pdf_bytes = _build_jpeg_pdf(pages)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(pdf_bytes)
        log.info("sips/naive merge: %d pages → %s", len(pages), output_path)
        return True

    except Exception as exc:
        log.error("sips approach failed: %s", exc)
        return False


def _jpeg_dimensions(data: bytes) -> tuple[int, int]:
    """Parse JPEG SOF marker to extract (width, height)."""
    i = 2  # skip FF D8
    while i < len(data) - 8:
        if data[i] != 0xFF:
            break
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2):  # SOF0/1/2
            h = (data[i + 5] << 8) | data[i + 6]
            w = (data[i + 7] << 8) | data[i + 8]
            return w, h
        seg_len = (data[i + 2] << 8) | data[i + 3]
        i += 2 + seg_len
    raise ValueError("Could not parse JPEG dimensions")


def _build_jpeg_pdf(pages: list[tuple[bytes, int, int]]) -> bytes:
    """
    Build a valid multi-page PDF embedding JPEG images using only Python stdlib.
    Object layout per page i (0-based):
      3+3i = Image XObject
      4+3i = Content stream
      5+3i = Page dict
    """
    buf = bytearray()
    offsets: dict[int, int] = {}

    def add_obj(num: int, data: bytes) -> None:
        offsets[num] = len(buf)
        buf.extend(f"{num} 0 obj\n".encode())
        buf.extend(data)
        buf.extend(b"\nendobj\n")

    n = len(pages)
    catalog_num = 1
    pages_num = 2
    img_nums     = [3 + 3 * i for i in range(n)]
    content_nums = [4 + 3 * i for i in range(n)]
    page_nums    = [5 + 3 * i for i in range(n)]

    buf += b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"

    # Catalog
    add_obj(catalog_num,
            f"<<\n/Type /Catalog\n/Pages {pages_num} 0 R\n>>".encode())

    # Pages dict
    kids = " ".join(f"{pn} 0 R" for pn in page_nums)
    add_obj(pages_num,
            f"<<\n/Type /Pages\n/Kids [{kids}]\n/Count {n}\n>>".encode())

    for i, (jpeg, w, h) in enumerate(pages):
        # Image XObject
        img_hdr = (
            f"<<\n/Type /XObject\n/Subtype /Image\n"
            f"/Width {w}\n/Height {h}\n"
            f"/ColorSpace /DeviceRGB\n/BitsPerComponent 8\n"
            f"/Filter /DCTDecode\n/Length {len(jpeg)}\n>>\n"
            f"stream\n"
        ).encode()
        add_obj(img_nums[i], img_hdr + jpeg + b"\nendstream")

        # Content stream: scale image to fill page
        content = f"q {w} 0 0 {h} 0 0 cm /Im Do Q".encode()
        cs_hdr = f"<<\n/Length {len(content)}\n>>\nstream\n".encode()
        add_obj(content_nums[i], cs_hdr + content + b"\nendstream")

        # Page dict
        add_obj(page_nums[i], (
            f"<<\n/Type /Page\n/Parent {pages_num} 0 R\n"
            f"/MediaBox [0 0 {w} {h}]\n"
            f"/Resources <<\n/XObject << /Im {img_nums[i]} 0 R >>\n>>\n"
            f"/Contents {content_nums[i]} 0 R\n>>"
        ).encode())

    # Cross-reference table
    xref_offset = len(buf)
    max_num = max(offsets)
    buf += b"xref\n"
    buf += f"0 {max_num + 1}\n".encode()
    buf += b"0000000000 65535 f \n"
    for num in range(1, max_num + 1):
        off = offsets.get(num, 0)
        buf += f"{off:010d} 00000 n \n".encode()

    buf += b"trailer\n"
    buf += f"<<\n/Size {max_num + 1}\n/Root {catalog_num} 0 R\n>>\n".encode()
    buf += b"startxref\n"
    buf += f"{xref_offset}\n".encode()
    buf += b"%%EOF\n"

    return bytes(buf)


# ── Main ───────────────────────────────────────────────────────────────────────
def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <image_dir> <output.pdf>")
        return 1

    image_dir   = sys.argv[1]
    output_path = sys.argv[2]

    png_files = sorted(glob.glob(os.path.join(image_dir, "*.png")))
    if not png_files:
        log.error("No PNG files found in %s", image_dir)
        return 1

    log.info("Starting PDF combine: %d frames → %s", len(png_files), output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    # Try best approach first, fall back if unavailable
    if combine_via_pdfkit(png_files, output_path):
        return 0

    log.info("PDFKit unavailable, falling back to sips")
    if combine_via_sips(png_files, output_path):
        return 0

    log.error("All PDF combine approaches failed")
    return 1


if __name__ == "__main__":
    sys.exit(main())
