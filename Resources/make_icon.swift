// Vẽ icon app (gradient cam-hồng + cốc cà phê) → PNG 1024px.
import AppKit
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.2, alpha: 1),
                    NSColor(calibratedRed: 0.96, green: 0.3, blue: 0.45, alpha: 1)])!.draw(in: path, angle: -60)
let cfg = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let s = sym.size
    sym.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
