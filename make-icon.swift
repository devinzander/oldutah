import AppKit
import ImageIO

// PNG fallback icon for iOS 18-25 (the AppIcon.icon document covers 26+).
let size: CGFloat = 1024
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let rgb = CGColorSpaceCreateDeviceRGB()

func ty(_ y: CGFloat) -> CGFloat { size - y }

// Utah red gradient background
let bg = CGGradient(colorsSpace: rgb, colors: [
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [137/255, 1/255, 0, 1])!,
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [137/255, 1/255, 0, 1])!,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Open book: two page panels + spine (same geometry as AppIcon.icon layers)
func page(mirrored: Bool) -> CGPath {
    func X(_ x: CGFloat) -> CGFloat { mirrored ? size - x : x }
    let p = CGMutablePath()
    p.move(to: CGPoint(x: X(512), y: ty(320)))
    p.addCurve(to: CGPoint(x: X(150), y: ty(285)),
               control1: CGPoint(x: X(440), y: ty(275)),
               control2: CGPoint(x: X(340), y: ty(260)))
    p.addLine(to: CGPoint(x: X(150), y: ty(690)))
    p.addCurve(to: CGPoint(x: X(512), y: ty(725)),
               control1: CGPoint(x: X(340), y: ty(665)),
               control2: CGPoint(x: X(440), y: ty(680)))
    p.closeSubpath()
    return p
}

// stacked under-pages for depth
for (dy, alpha) in [(48.0, 0.5), (32.0, 0.62), (16.0, 0.76)] {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: -dy)
    for path in [page(mirrored: false), page(mirrored: true)] {
        ctx.addPath(path)
        ctx.setFillColor(CGColor(red: 0.953, green: 0.925, blue: 0.871, alpha: alpha))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

for path in [page(mirrored: false), page(mirrored: true)] {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                  color: CGColor(red: 0.2, green: 0.02, blue: 0, alpha: 0.4))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.953, green: 0.925, blue: 0.871, alpha: 0.97))
    ctx.fillPath()
    ctx.restoreGState()
}
// spine
ctx.addPath(CGPath(roundedRect: CGRect(x: 502, y: ty(728), width: 20, height: 412), cornerWidth: 10, cornerHeight: 10, transform: nil))
ctx.setFillColor(CGColor(red: 0.88, green: 0.83, blue: 0.74, alpha: 1))
ctx.fillPath()


let cg = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out.path)")
