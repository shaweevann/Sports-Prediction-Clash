// Draws the Sports Prediction Clash app icon: a football in flight through a polished gold laurel crown,
// over a burgundy field with jersey stripes.
// Usage: swift clash_icon.swift <out.png>
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ClashIcon.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let space = CGColorSpaceCreateDeviceRGB()
func gradient(_ stops: [(UInt32, CGFloat)], alpha: CGFloat = 1) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { rgb($0.0, alpha) } as CFArray, locations: stops.map { $0.1 })!
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ns = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ns
let c = ns.cgContext
c.translateBy(x: 0, y: S); c.scaleBy(x: 1, y: -1)   // top-left origin

// MARK: Burgundy field
c.drawRadialGradient(gradient([(0xA3243A, 0), (0x7A1427, 0.45), (0x4A0A17, 0.85), (0x2E050D, 1)]),
                     startCenter: CGPoint(x: 512, y: 430), startRadius: 0, endCenter: CGPoint(x: 512, y: 520), endRadius: 760,
                     options: [.drawsAfterEndLocation])
// Soft sheen across the top, like lacquer
c.saveGState()
c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0xFFD9DF, 0.16), rgb(0xFFD9DF, 0)] as CFArray, locations: [0, 1])!,
                     startCenter: CGPoint(x: 400, y: 220), startRadius: 0, endCenter: CGPoint(x: 400, y: 220), endRadius: 520, options: [])
c.restoreGState()

// MARK: Jersey stripes
// Two bold sleeve stripes and a gold pinstripe sweeping up to the right, for motion
c.saveGState()
c.translateBy(x: 512, y: 512); c.rotate(by: -0.52)
for (y, h, color, a) in [(-250.0, 70.0, 0x3A0510, 0.32), (-150.0, 26.0, 0xFFD24A, 0.13), (150.0, 70.0, 0x3A0510, 0.32), (250.0, 26.0, 0xFFD24A, 0.13)] as [(CGFloat, CGFloat, UInt32, CGFloat)] {
    c.setFillColor(rgb(color, a))
    c.fill(CGRect(x: -900, y: y - h / 2, width: 1800, height: h))
}
c.restoreGState()

// MARK: Laurel crown
let center = CGPoint(x: 512, y: 528)
let radius: CGFloat = 316
func point(_ deg: CGFloat, _ r: CGFloat = radius) -> CGPoint {
    let t = deg * .pi / 180
    return CGPoint(x: center.x + r * cos(t), y: center.y + r * sin(t))   // y points down: 90° is the bottom
}

/// Polished metal: one light from the upper left, so the whole crown shares the same bright and dark bands.
let metal = gradient([(0xFFFCEB, 0), (0xFFDF6B, 0.12), (0xE9A919, 0.26), (0x9C6205, 0.36), (0xFFF3C2, 0.46), (0xFFD24A, 0.54),
                      (0xC8860F, 0.66), (0x7A4704, 0.77), (0xF0B92C, 0.88), (0xFFF4C8, 1)])
func fillMetal(_ path: CGPath) {
    c.saveGState()
    c.addPath(path); c.clip()
    c.drawLinearGradient(metal, start: CGPoint(x: 150, y: 150), end: CGPoint(x: 880, y: 900), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func dropShadow(_ path: CGPath) {
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: 12), blur: 20, color: rgb(0x14010A, 0.65))
    c.addPath(path); c.setFillColor(rgb(0x8A5810)); c.fillPath()
    c.restoreGState()
}

struct Leaf { let path: CGPath, half: CGPath, base: CGPoint, angle: CGFloat, length: CGFloat }

/// A laurel leaf from `base` along `angle`, plus its shaded half (one side of the center vein) for the folded look.
func makeLeaf(base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, shadeSide: CGFloat) -> Leaf {
    let t = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle)
    let p = CGMutablePath()
    p.move(to: .zero, transform: t)
    p.addCurve(to: CGPoint(x: length, y: 0), control1: CGPoint(x: length * 0.22, y: -width), control2: CGPoint(x: length * 0.72, y: -width * 0.85), transform: t)
    p.addCurve(to: .zero, control1: CGPoint(x: length * 0.72, y: width * 0.85), control2: CGPoint(x: length * 0.22, y: width), transform: t)
    p.closeSubpath()
    let h = CGMutablePath()
    h.move(to: .zero, transform: t)
    h.addCurve(to: CGPoint(x: length, y: 0), control1: CGPoint(x: length * 0.22, y: shadeSide * width), control2: CGPoint(x: length * 0.72, y: shadeSide * width * 0.85), transform: t)
    h.closeSubpath()
    return Leaf(path: p, half: h, base: base, angle: angle, length: length)
}

func drawLeaf(_ l: Leaf) {
    fillMetal(l.path)
    // Folded along the vein: the half facing away from the light sits in shadow
    c.saveGState()
    c.addPath(l.half); c.setFillColor(rgb(0x3A1C00, 0.28)); c.fillPath()
    c.restoreGState()
    // Vein and rim
    c.saveGState()
    c.setLineCap(.round)
    c.setStrokeColor(rgb(0x6B420A, 0.75)); c.setLineWidth(2.5)
    c.move(to: CGPoint(x: l.base.x + cos(l.angle) * l.length * 0.08, y: l.base.y + sin(l.angle) * l.length * 0.08))
    c.addLine(to: CGPoint(x: l.base.x + cos(l.angle) * l.length * 0.9, y: l.base.y + sin(l.angle) * l.length * 0.9))
    c.strokePath()
    c.addPath(l.path); c.setStrokeColor(rgb(0xFFF3C4, 0.55)); c.setLineWidth(2); c.strokePath()
    c.restoreGState()
}

var leaves: [Leaf] = []
var stems: [CGPath] = []
/// One branch along the circle; `dir` = -1 for the left branch, 1 for the right.
func branch(dir: CGFloat) {
    let start: CGFloat = dir < 0 ? 98 : 82         // meets the other branch at the bottom
    let end: CGFloat = dir < 0 ? 252 : -72         // stops short of the top, leaving the crown open
    let stem = CGMutablePath()
    stem.addArc(center: center, radius: radius, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: dir > 0)
    stems.append(stem.copy(strokingWithWidth: 18, lineCap: .round, lineJoin: .round, miterLimit: 4))
    let steps = 12
    for k in 0..<steps {
        let f = CGFloat(k) / CGFloat(steps - 1)
        let deg = start + (end - start) * (0.06 + 0.94 * f)
        let base = point(deg)
        let tangent = (deg + (dir < 0 ? 90 : -90)) * .pi / 180     // growth direction, toward the top
        let size = 0.6 + 0.4 * sin(min(1, f * 1.15) * .pi)          // biggest mid-branch
        for side in [-1.0, 1.0] as [CGFloat] {
            let a = tangent + side * dir * 0.6
            leaves.append(makeLeaf(base: base, angle: a, length: 158 * size, width: 38 * size, shadeSide: side * dir))
        }
    }
    let tipDeg = end
    leaves.append(makeLeaf(base: point(tipDeg), angle: (tipDeg + (dir < 0 ? 90 : -90)) * .pi / 180, length: 128, width: 28, shadeSide: dir))
}
branch(dir: -1)
branch(dir: 1)

// Warm glow behind the gold so it lifts off the burgundy
c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0xFFC45A, 0), rgb(0xFFC45A, 0.09), rgb(0xFFC45A, 0)] as CFArray, locations: [0.66, 0.8, 0.95])!,
                     startCenter: center, startRadius: 0, endCenter: center, endRadius: radius + 190, options: [])
// Shadows first so no leaf's shadow falls on top of its neighbor's gold
for s in stems { dropShadow(s) }
for l in leaves { dropShadow(l.path) }
for s in stems { fillMetal(s) }
for l in leaves { drawLeaf(l) }

// MARK: Bow tying the branches together at the base
let knot = point(90)
func bowLoop(_ side: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: knot)
    p.addCurve(to: knot, control1: CGPoint(x: knot.x + side * 150, y: knot.y - 90), control2: CGPoint(x: knot.x + side * 150, y: knot.y + 70))
    return p
}
func tail(_ side: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: knot.x + side * 10, y: knot.y + 6))
    p.addCurve(to: CGPoint(x: knot.x + side * 84, y: knot.y + 104), control1: CGPoint(x: knot.x + side * 36, y: knot.y + 40), control2: CGPoint(x: knot.x + side * 64, y: knot.y + 72))
    p.addLine(to: CGPoint(x: knot.x + side * 56, y: knot.y + 120))
    p.addLine(to: CGPoint(x: knot.x + side * 54, y: knot.y + 96))
    p.addCurve(to: CGPoint(x: knot.x - side * 4, y: knot.y + 16), control1: CGPoint(x: knot.x + side * 40, y: knot.y + 70), control2: CGPoint(x: knot.x + side * 18, y: knot.y + 40))
    p.closeSubpath()
    return p
}
let knotPath = CGPath(roundedRect: CGRect(x: knot.x - 30, y: knot.y - 26, width: 60, height: 52), cornerWidth: 18, cornerHeight: 18, transform: nil)
for side in [-1.0, 1.0] as [CGFloat] { dropShadow(tail(side)); dropShadow(bowLoop(side)) }
dropShadow(knotPath)
for side in [-1.0, 1.0] as [CGFloat] {
    fillMetal(tail(side))
    let loop = bowLoop(side)
    fillMetal(loop)
    // Inside of the loop in shadow, rim catching light
    c.saveGState()
    c.addPath(loop); c.clip()
    c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0x3A1C00, 0.45), rgb(0x3A1C00, 0)] as CFArray, locations: [0, 1])!,
                         startCenter: CGPoint(x: knot.x + side * 70, y: knot.y - 4), startRadius: 0,
                         endCenter: CGPoint(x: knot.x + side * 70, y: knot.y - 4), endRadius: 46, options: [])
    c.restoreGState()
    c.addPath(loop); c.setStrokeColor(rgb(0xFFF3C4, 0.6)); c.setLineWidth(2.5); c.strokePath()
}
fillMetal(knotPath)
c.addPath(knotPath); c.setStrokeColor(rgb(0xFFF3C4, 0.7)); c.setLineWidth(2.5); c.strokePath()

// MARK: Football in flight
func add(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat = 1) -> CGPoint { CGPoint(x: a.x + b.x * k, y: a.y + b.y * k) }
let ballCenter = CGPoint(x: 528, y: 506)
let ballAngle: CGFloat = -0.6                       // nose up and to the right
let ballL: CGFloat = 400, ballW: CGFloat = 236
let fwd = CGPoint(x: cos(ballAngle), y: sin(ballAngle)), side = CGPoint(x: -sin(ballAngle), y: cos(ballAngle))

// Speed streaks trailing down-left, fading out
c.saveGState()
for (off, startD, len, w) in [(-70.0, 96.0, 200.0, 15.0), (-22.0, 120.0, 260.0, 20.0), (28.0, 116.0, 230.0, 17.0), (74.0, 90.0, 170.0, 12.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    let p0 = add(add(ballCenter, fwd, -startD), side, off), p1 = add(p0, fwd, -len)
    let streak = CGMutablePath(); streak.move(to: p0); streak.addLine(to: p1)
    c.saveGState()
    c.addPath(streak.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 2)); c.clip()
    c.drawLinearGradient(CGGradient(colorsSpace: space, colors: [rgb(0xFFF1B8, 0.95), rgb(0xFFC93C, 0.55), rgb(0xFFC93C, 0)] as CFArray, locations: [0, 0.45, 1])!,
                         start: p0, end: p1, options: [])
    c.restoreGState()
}
c.restoreGState()

c.saveGState()
c.translateBy(x: ballCenter.x, y: ballCenter.y); c.rotate(by: ballAngle)
let ball = CGMutablePath()
ball.move(to: CGPoint(x: -ballL / 2, y: 0))
ball.addCurve(to: CGPoint(x: ballL / 2, y: 0), control1: CGPoint(x: -ballL * 0.3, y: -ballW * 0.68), control2: CGPoint(x: ballL * 0.3, y: -ballW * 0.68))
ball.addCurve(to: CGPoint(x: -ballL / 2, y: 0), control1: CGPoint(x: ballL * 0.3, y: ballW * 0.68), control2: CGPoint(x: -ballL * 0.3, y: ballW * 0.68))
ball.closeSubpath()
// Shadow, then leather lit from the upper left
c.saveGState()
c.setShadow(offset: CGSize(width: 10, height: 18), blur: 26, color: rgb(0x14010A, 0.7))
c.addPath(ball); c.setFillColor(rgb(0x5A2A0E)); c.fillPath()
c.restoreGState()
c.saveGState()
c.addPath(ball); c.clip()
c.drawRadialGradient(gradient([(0xC97A3E, 0), (0x9A4E22, 0.4), (0x6A3010, 0.75), (0x3A1806, 1)]),
                     startCenter: CGPoint(x: -ballL * 0.12, y: -ballW * 0.28), startRadius: 0,
                     endCenter: CGPoint(x: 0, y: 0), endRadius: ballL * 0.6, options: [.drawsAfterEndLocation])
// White stripes near each tip, bending with the ball
c.setStrokeColor(rgb(0xFFF8EC)); c.setLineWidth(15)
for x in [-ballL * 0.31, ballL * 0.31] {
    let bend: CGFloat = x < 0 ? -14 : 14
    c.move(to: CGPoint(x: x, y: -ballW * 0.5)); c.addQuadCurve(to: CGPoint(x: x, y: ballW * 0.5), control: CGPoint(x: x + bend, y: 0))
}
c.strokePath()
// Seam along the length
c.setStrokeColor(rgb(0x2A1004, 0.55)); c.setLineWidth(3)
c.move(to: CGPoint(x: -ballL * 0.46, y: -6)); c.addQuadCurve(to: CGPoint(x: ballL * 0.46, y: -6), control: CGPoint(x: 0, y: -ballW * 0.14)); c.strokePath()
// Gloss
c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.38), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!,
                     startCenter: CGPoint(x: -ballL * 0.14, y: -ballW * 0.3), startRadius: 0,
                     endCenter: CGPoint(x: -ballL * 0.14, y: -ballW * 0.3), endRadius: ballL * 0.24, options: [])
c.restoreGState()
// Laces, sitting just above center so the ball reads as round
c.setLineCap(.round)
c.setStrokeColor(rgb(0x2A1004, 0.35)); c.setLineWidth(12)
c.move(to: CGPoint(x: -ballL * 0.17, y: -ballW * 0.1 + 3)); c.addLine(to: CGPoint(x: ballL * 0.17, y: -ballW * 0.1 + 3)); c.strokePath()
c.setStrokeColor(rgb(0xFFFAF0)); c.setLineWidth(9)
c.move(to: CGPoint(x: -ballL * 0.17, y: -ballW * 0.1)); c.addLine(to: CGPoint(x: ballL * 0.17, y: -ballW * 0.1)); c.strokePath()
c.setLineWidth(8)
for k in 0..<7 {
    let x = -ballL * 0.15 + CGFloat(k) * ballL * 0.05
    c.move(to: CGPoint(x: x, y: -ballW * 0.1 - 19)); c.addLine(to: CGPoint(x: x, y: -ballW * 0.1 + 19))
}
c.strokePath()
// Gold rim ties the ball to the crown
c.addPath(ball); c.setStrokeColor(rgb(0xFFD866, 0.9)); c.setLineWidth(5); c.strokePath()
c.restoreGState()

// MARK: Glints
func sparkle(_ p: CGPoint, _ r: CGFloat) {
    c.saveGState()
    c.drawRadialGradient(CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.95), rgb(0xFFF1C0, 0.5), rgb(0xFFF1C0, 0)] as CFArray, locations: [0, 0.25, 1])!,
                         startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    c.setFillColor(rgb(0xFFFFFF, 0.9))
    let star = CGMutablePath()
    star.move(to: CGPoint(x: p.x, y: p.y - r * 1.4))
    star.addQuadCurve(to: CGPoint(x: p.x + r * 1.4, y: p.y), control: p)
    star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r * 1.4), control: p)
    star.addQuadCurve(to: CGPoint(x: p.x - r * 1.4, y: p.y), control: p)
    star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r * 1.4), control: p)
    c.addPath(star); c.fillPath()
    c.restoreGState()
}
sparkle(point(212, radius + 30), 30)
sparkle(point(-34, radius + 40), 22)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
