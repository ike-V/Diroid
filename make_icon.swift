import AppKit

let size = 1024.0
let canvasSize = NSSize(width: size, height: size)
let canvasRect = NSRect(origin: .zero, size: canvasSize)

// Step 1: render the folder glyph as a white silhouette on a transparent canvas,
// padded well inside the edges (not a hand-drawn full-bleed background) — this is
// what lets macOS's own adaptive icon system apply its own black/white plate behind
// it under Dark/Light/Tinted icon styles instead of falling back to synthesizing one.
let sizeConfig = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let combinedConfig = sizeConfig.applying(colorConfig)

guard let symbol = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(combinedConfig) else {
    print("failed to load symbol")
    exit(1)
}

let maskImage = NSImage(size: canvasSize)
maskImage.lockFocus()
let symSize = symbol.size
let origin = NSPoint(x: (size - symSize.width) / 2, y: (size - symSize.height) / 2)
symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
maskImage.unlockFocus()

// Step 2: composite the official Android green (#3DDC84, source.android.com brand color)
// through that silhouette, so only the glyph shape picks up color.
maskImage.lockFocus()
NSGraphicsContext.current?.compositingOperation = .sourceAtop
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0x3D / 255.0, green: 0xDC / 255.0, blue: 0x84 / 255.0, alpha: 1.0),
    NSColor(calibratedRed: 0x17 / 255.0, green: 0x8A / 255.0, blue: 0x52 / 255.0, alpha: 1.0),
])
gradient?.draw(in: canvasRect, angle: -90)
maskImage.unlockFocus()

guard let tiff = maskImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("failed to render icon")
    exit(1)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outURL)
print("wrote \(outURL.path)")
