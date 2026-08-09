import AppKit

/// The status-item icon, drawn in code as a template image so it stays crisp
/// at any backing scale and picks up the menu bar's light/dark tinting.
/// Mirrors the app icon: a mic that steams while it's being kept awake.
enum MenuBarIcon {
  static let active: NSImage = make(steaming: true)
  static let idle: NSImage = make(steaming: false)

  private static let canvas = NSSize(width: 18, height: 18)

  private static func make(steaming: Bool) -> NSImage {
    let image = NSImage(size: canvas, flipped: false) { _ in
      // With steam the composition is taller, so the mic sits lower to keep
      // the whole glyph optically centered in the menu bar.
      draw(baseY: steaming ? 1.2 : 4.0, steaming: steaming)
      return true
    }
    image.isTemplate = true
    return image
  }

  /// Draws the mic with its base bar at `baseY`. Template images only use
  /// alpha, so everything is drawn in black.
  private static func draw(baseY: CGFloat, steaming: Bool) {
    NSColor.black.setFill()
    NSColor.black.setStroke()

    let capsule = NSBezierPath(
      roundedRect: NSRect(x: 6.9, y: baseY + 3.3, width: 4.2, height: 6.6),
      xRadius: 2.1, yRadius: 2.1)
    capsule.fill()

    let yokeCenter = NSPoint(x: 9, y: baseY + 5.1)
    let yoke = NSBezierPath()
    yoke.lineWidth = 1.4
    yoke.lineCapStyle = .round
    yoke.move(to: NSPoint(x: 5.1, y: baseY + 5.9))
    yoke.line(to: NSPoint(x: 5.1, y: yokeCenter.y))
    yoke.appendArc(
      withCenter: yokeCenter, radius: 3.9, startAngle: 180, endAngle: 360, clockwise: false)
    yoke.line(to: NSPoint(x: 12.9, y: baseY + 5.9))
    yoke.stroke()

    let stem = NSBezierPath()
    stem.lineWidth = 1.4
    stem.lineCapStyle = .round
    stem.move(to: NSPoint(x: 9, y: yokeCenter.y - 3.9))
    stem.line(to: NSPoint(x: 9, y: baseY))
    stem.stroke()

    let base = NSBezierPath()
    base.lineWidth = 1.4
    base.lineCapStyle = .round
    base.move(to: NSPoint(x: 5.5, y: baseY))
    base.line(to: NSPoint(x: 12.5, y: baseY))
    base.stroke()

    guard steaming else { return }

    let capsuleTop = baseY + 9.9
    drawSteamWisp(
      from: NSPoint(x: 9, y: capsuleTop + 1.0), height: 4.0, width: 1.2, alpha: 0.9)
    drawSteamWisp(
      from: NSPoint(x: 6.2, y: capsuleTop + 0.8), height: 3.2, width: 1.0, alpha: 0.6)
    drawSteamWisp(
      from: NSPoint(x: 11.8, y: capsuleTop + 0.8), height: 3.2, width: 1.0, alpha: 0.6)
  }

  /// A single S-curved steam wisp rising from `from`.
  private static func drawSteamWisp(
    from: NSPoint, height: CGFloat, width: CGFloat, alpha: CGFloat
  ) {
    NSColor.black.withAlphaComponent(alpha).setStroke()
    let wisp = NSBezierPath()
    wisp.lineWidth = width
    wisp.lineCapStyle = .round
    wisp.move(to: from)
    wisp.curve(
      to: NSPoint(x: from.x, y: from.y + height),
      controlPoint1: NSPoint(x: from.x - 1.2, y: from.y + height * 0.35),
      controlPoint2: NSPoint(x: from.x + 1.2, y: from.y + height * 0.65))
    wisp.stroke()
  }
}
