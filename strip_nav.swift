// strip_nav.swift
// Detects and removes the static left nav panel from Apple News screenshots
// using frame differencing: columns where pixels don't change between frame 0
// and frame 1 are static UI (nav); columns that change are scrolling content.
//
// Usage:  strip_nav <image_dir>
// Exit codes:
//   0 — nav detected and whited-out in all frames
//   2 — no nav detected (full width is content, or only 1 frame)
//   1 — error

import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: strip_nav <image_dir>\n", stderr)
    exit(1)
}

let dir = CommandLine.arguments[1]

// ── Collect sorted frame paths ──────────────────────────────────────────────
let fm = FileManager.default
guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
    fputs("Cannot list directory: \(dir)\n", stderr)
    exit(1)
}
let frames = entries
    .filter { $0.hasSuffix(".png") }
    .sorted()
    .map    { dir + "/" + $0 }

guard frames.count >= 2 else {
    fputs("Need at least 2 frames to detect nav; skipping.\n", stderr)
    exit(2)
}

// ── Load raw pixels for two frames ─────────────────────────────────────────
func loadPixels(_ path: String) -> (pixels: [UInt8], w: Int, h: Int, bpr: Int)? {
    let url = URL(fileURLWithPath: path)
    guard
        let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }

    let w   = img.width
    let h   = img.height
    let bpp = 4
    let bpr = w * bpp
    var buf = [UInt8](repeating: 0, count: h * bpr)
    let cs  = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: bpr, space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buf, w, h, bpr)
}

guard
    let f0 = loadPixels(frames[0]),
    let f1 = loadPixels(frames[1]),
    f0.w == f1.w, f0.h == f1.h
else {
    fputs("Could not load frames or size mismatch.\n", stderr)
    exit(1)
}

let imgW = f0.w
let imgH = f0.h
let bpr  = f0.bpr
let p0   = f0.pixels
let p1   = f1.pixels

// ── Find nav panel width via column-diff analysis ──────────────────────────
// For each column x, count how many rows have a meaningful brightness
// difference between frame 0 and frame 1.
// Nav columns: < 4 % of rows differ  (static UI)
// Content columns: ≥ 4 % differ       (scrolling text/images)
// Only scan the leftmost 40 % of the image to avoid false positives from
// right-edge scrollbars or other static chrome.

let maxScanX    = imgW * 40 / 100
let diffThresh  = 20    // pixel brightness difference ≥ 20 counts as "changed"
let rowFracReq  = 0.04  // 4 % of rows must differ to call it "content"

var navWidth = 0

for x in 0..<maxScanX {
    var diffRows = 0
    for y in 0..<imgH {
        let i = y * bpr + x * 4
        let r = abs(Int(p0[i])     - Int(p1[i]))
        let g = abs(Int(p0[i + 1]) - Int(p1[i + 1]))
        let b = abs(Int(p0[i + 2]) - Int(p1[i + 2]))
        if r > diffThresh || g > diffThresh || b > diffThresh { diffRows += 1 }
    }
    let frac = Double(diffRows) / Double(imgH)
    if frac >= rowFracReq {
        navWidth = x
        break
    }
}

// Require a meaningful nav width — ignore sub-pixel noise
let minNavPx = 40
guard navWidth >= minNavPx else {
    fputs("No nav panel detected (nav_width=\(navWidth) < \(minNavPx)px).\n", stderr)
    exit(2)
}

fputs("Nav panel detected: \(navWidth)px wide — whiting out in \(frames.count) frame(s).\n", stderr)

// ── White out the nav column in every frame ─────────────────────────────────
var failCount = 0
for framePath in frames {
    let url = URL(fileURLWithPath: framePath)
    guard
        let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else {
        fputs("Skipping (could not load): \(framePath)\n", stderr)
        failCount += 1
        continue
    }

    let w   = img.width
    let h   = img.height
    let cs  = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fputs("Skipping (bitmap ctx failed): \(framePath)\n", stderr)
        failCount += 1
        continue
    }

    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: navWidth, height: h))

    guard let result = ctx.makeImage() else {
        fputs("Skipping (makeImage failed): \(framePath)\n", stderr)
        failCount += 1
        continue
    }

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("Skipping (dest failed): \(framePath)\n", stderr)
        failCount += 1
        continue
    }
    CGImageDestinationAddImage(dest, result, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("Skipping (finalize failed): \(framePath)\n", stderr)
        failCount += 1
    }
}

fputs("Done. Nav stripped from \(frames.count - failCount)/\(frames.count) frames.\n", stderr)
exit(0)
