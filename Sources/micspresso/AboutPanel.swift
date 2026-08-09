import AppKit
import MicspressoCore

/// Presents the standard macOS About panel with Micspresso's details.
enum AboutPanel {
  static func show() {
    // Accessory apps aren't frontmost when a status item is clicked; without
    // activation the panel opens behind other windows.
    if #available(macOS 14.0, *) {
      NSApp.activate()
    } else {
      NSApp.activate(ignoringOtherApps: true)
    }
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "Micspresso",
      .applicationVersion: AppInfo.version,
      .credits: credits(),
    ])
  }

  private static func credits() -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 2
    let base: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11),
      .paragraphStyle: paragraph,
      .foregroundColor: NSColor.labelColor,
    ]

    func line(_ text: String, link: String? = nil) -> NSAttributedString {
      var attributes = base
      if let link {
        attributes[.link] = URL(string: link)!
      }
      return NSAttributedString(string: text, attributes: attributes)
    }

    let credits = NSMutableAttributedString()
    credits.append(line("Keeps your Bluetooth mic awake so dictation starts instantly.\n\n"))
    credits.append(line("A MoltenBits project\n", link: "https://github.com/moltenbits"))
    credits.append(
      line(
        "github.com/moltenbits/micspresso\n",
        link: "https://github.com/moltenbits/micspresso"))
    credits.append(
      line(
        "MIT License",
        link: "https://github.com/moltenbits/micspresso/blob/main/LICENSE"))
    return credits
  }
}
