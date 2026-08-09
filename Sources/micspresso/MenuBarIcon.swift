import AppKit

/// The status-item icon, drawn in code as a template image so it stays crisp
/// at any backing scale and picks up the menu bar's light/dark tinting.
/// Mirrors the app icon: a mic that steams while it's being kept awake.
enum MenuBarIcon {
  static let active: NSImage = make(steaming: true)
  static let idle: NSImage = make(steaming: false)

  private static let canvas = NSSize(width: 18, height: 18)
  /// Mic glyph height in unit coordinates (base bar to capsule top).
  private static let micUnits: CGFloat = 9.9
  /// Extra units above the mic for the steam (gap + wisps).
  private static let steamUnits: CGFloat = 3.9

  private static func make(steaming: Bool) -> NSImage {
    // Without steam, the mic grows to fill the vertical space the steam
    // otherwise occupies; with steam, the mic shrinks to make room for it.
    let contentUnits = steaming ? micUnits + steamUnits : micUnits
    let scale = steaming ? 1.2 : 1.55
    let baseY = (canvas.height - contentUnits * scale) / 2
    let image = NSImage(size: canvas, flipped: false) { _ in
      draw(baseY: baseY, scale: scale, steaming: steaming)
      return true
    }
    image.isTemplate = true
    return image
  }

  /// Draws the mic with its base bar at `baseY`. Geometry is authored in
  /// unit coordinates around the center line (x 0) and the base (y 0), then
  /// scaled. Template images only use alpha, so everything is black.
  private static func draw(baseY: CGFloat, scale: CGFloat, steaming: Bool) {
    func at(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint {
      NSPoint(x: 9 + dx * scale, y: baseY + dy * scale)
    }
    // Strokes scale with the glyph so proportions match between states.
    let strokeWidth = 1.25 * scale

    NSColor.black.setFill()
    NSColor.black.setStroke()

    let capsuleOrigin = at(-2.1, 3.3)
    let capsule = NSBezierPath(
      roundedRect: NSRect(
        origin: capsuleOrigin, size: NSSize(width: 4.2 * scale, height: 6.6 * scale)),
      xRadius: 2.1 * scale, yRadius: 2.1 * scale)
    capsule.fill()

    let yoke = NSBezierPath()
    yoke.lineWidth = strokeWidth
    yoke.lineCapStyle = .round
    yoke.move(to: at(-3.9, 5.9))
    yoke.line(to: at(-3.9, 5.1))
    yoke.appendArc(
      withCenter: at(0, 5.1), radius: 3.9 * scale, startAngle: 180, endAngle: 360,
      clockwise: false)
    yoke.line(to: at(3.9, 5.9))
    yoke.stroke()

    let stem = NSBezierPath()
    stem.lineWidth = strokeWidth
    stem.lineCapStyle = .round
    stem.move(to: at(0, 1.2))
    stem.line(to: at(0, 0))
    stem.stroke()

    let base = NSBezierPath()
    base.lineWidth = strokeWidth
    base.lineCapStyle = .round
    base.move(to: at(-3.5, 0))
    base.line(to: at(3.5, 0))
    base.stroke()

    guard steaming else { return }

    drawSteamWisp(from: at(0, 10.6), height: 3.2 * scale, width: 1.15, alpha: 0.9)
    drawSteamWisp(from: at(-2.8, 10.4), height: 2.6 * scale, width: 0.95, alpha: 0.6)
    drawSteamWisp(from: at(2.8, 10.4), height: 2.6 * scale, width: 0.95, alpha: 0.6)
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
      controlPoint1: NSPoint(x: from.x - 1.3, y: from.y + height * 0.35),
      controlPoint2: NSPoint(x: from.x + 1.3, y: from.y + height * 0.65))
    wisp.stroke()
  }
}
