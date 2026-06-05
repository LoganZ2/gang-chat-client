import Cocoa
import FlutterMacOS

private let loginWindowSize = NSSize(width: 430, height: 256)
private let resizeCursorEdgeWidth: CGFloat = 8
private let appBackground = NSColor(
  red: CGFloat(0x14) / 255.0,
  green: CGFloat(0x17) / 255.0,
  blue: CGFloat(0x1D) / 255.0,
  alpha: 1
)

class MainFlutterWindow: NSWindow {
  private var resizeCursorActive = false

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
    isRestorable = false
    animationBehavior = .none

    setInitialLoginFrame()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    updateResizeCursor(for: event.locationInWindow)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    resetResizeCursorIfNeeded()
  }

  // window_manager's setTitleBarStyle("hidden") flips isOpaque to false. Pin
  // opacity so the window stays opaque and avoids a black strip.
  override var isOpaque: Bool {
    get { true }
    set {}
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

  private func updateResizeCursor(for location: NSPoint) {
    guard styleMask.contains(.resizable) else {
      resetResizeCursorIfNeeded()
      return
    }

    let width = frame.width
    let height = frame.height
    let left = location.x <= resizeCursorEdgeWidth
    let right = location.x >= width - resizeCursorEdgeWidth
    let bottom = location.y <= resizeCursorEdgeWidth
    let top = location.y >= height - resizeCursorEdgeWidth

    if left || right {
      NSCursor.resizeLeftRight.set()
      resizeCursorActive = true
      return
    }

    if top || bottom {
      NSCursor.resizeUpDown.set()
      resizeCursorActive = true
      return
    }

    resetResizeCursorIfNeeded()
  }

  private func resetResizeCursorIfNeeded() {
    if !resizeCursorActive { return }
    NSCursor.arrow.set()
    resizeCursorActive = false
  }
}
