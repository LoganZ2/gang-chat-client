import Cocoa
import FlutterMacOS

private let loginWindowSize = NSSize(width: 430, height: 288)
private let appBackground = NSColor(
  red: CGFloat(0x14) / 255.0,
  green: CGFloat(0x17) / 255.0,
  blue: CGFloat(0x1D) / 255.0,
  alpha: 1
)

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    alphaValue = 0

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.acceptsMouseMovedEvents = true

    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    styleMask.remove(.resizable)
    backgroundColor = appBackground
    isOpaque = true
    hasShadow = false
    isRestorable = false
    animationBehavior = .none

    setInitialLoginFrame()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func setInitialLoginFrame() {
    let screenFrame = NSScreen.main?.visibleFrame ?? frame
    let windowFrame = NSRect(
      x: screenFrame.origin.x + (screenFrame.width - loginWindowSize.width) / 2,
      y: screenFrame.origin.y + (screenFrame.height - loginWindowSize.height) / 2,
      width: loginWindowSize.width,
      height: loginWindowSize.height
    )
    minSize = loginWindowSize
    maxSize = loginWindowSize
    setFrame(windowFrame, display: true)
  }
}
