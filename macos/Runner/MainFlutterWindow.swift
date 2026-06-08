import Cocoa
import CoreGraphics
import FlutterMacOS

private let loginWindowSize = NSSize(width: 430, height: 256)
private let resizeCursorEdgeWidth: CGFloat = 8
// Logical height of the v2 Flutter title bar. The native traffic lights are
// vertically centered within this band. Keep in sync with `_homeTitleBarHeight`
// in lib/src/v2/home_shell_title_bar.dart.
private let v2TitleBarHeight: CGFloat = 44
private let screenThumbnailChannel = "gang_chat/screen_thumbnail"
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

    registerScreenThumbnailChannel(flutterViewController)
    RegisterGeneratedPlugins(registry: flutterViewController)

    // AppKit re-pins the traffic lights to the top edge on resize and key
    // changes, so re-center them on those events as well as once after setup.
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(repositionTrafficLights),
      name: NSWindow.didResizeNotification,
      object: self
    )
    center.addObserver(
      self,
      selector: #selector(repositionTrafficLights),
      name: NSWindow.didBecomeKeyNotification,
      object: self
    )
    DispatchQueue.main.async { [weak self] in self?.repositionTrafficLights() }

    super.awakeFromNib()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // Centers the native traffic lights within the v2 title-bar band and insets
  // them from the left so the surrounding gap is even on all sides. No-op while
  // the buttons are hidden (e.g. the login window), so it is safe to call
  // unconditionally.
  @objc private func repositionTrafficLights() {
    let buttons: [NSButton] = [
      standardWindowButton(.closeButton),
      standardWindowButton(.miniaturizeButton),
      standardWindowButton(.zoomButton),
    ].compactMap { $0 }

    guard let titleBarView = buttons.first?.superview,
      let closeButton = buttons.first
    else { return }

    // Match the left gap to the vertical gap so the lights look evenly inset.
    let sideGap = (v2TitleBarHeight - closeButton.frame.height) / 2
    let dx = sideGap - closeButton.frame.origin.x

    for button in buttons where !button.isHidden {
      let buttonHeight = button.frame.height
      // Center the button within a band of `v2TitleBarHeight` measured from the
      // top of the title bar view. The title bar uses non-flipped coordinates
      // (y grows upward), so the top edge sits at the view's full height.
      let originY: CGFloat
      if titleBarView.isFlipped {
        originY = (v2TitleBarHeight - buttonHeight) / 2
      } else {
        originY = titleBarView.frame.height - v2TitleBarHeight / 2 - buttonHeight / 2
      }
      button.setFrameOrigin(NSPoint(x: button.frame.origin.x + dx, y: originY))
    }
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

  // The screen-share picker's thumbnails come from libwebrtc's RTCDesktopSource,
  // whose screen grabber shears frames on Retina displays (the same stride bug
  // the live share avoids by using ScreenCaptureKit). CGDisplayCreateImage lets
  // CoreGraphics own the buffer stride, so the thumbnail comes back undistorted.
  private func registerScreenThumbnailChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: screenThumbnailChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "captureScreenThumbnail":
        guard
          let args = call.arguments as? [String: Any],
          let displayIdString = args["displayId"] as? String,
          let displayId = CGDirectDisplayID(displayIdString)
        else {
          result(nil)
          return
        }
        let maxWidth = (args["maxWidth"] as? NSNumber)?.intValue ?? 320
        result(self.captureScreenThumbnail(displayId: displayId, maxWidth: maxWidth))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func captureScreenThumbnail(displayId: CGDirectDisplayID, maxWidth: Int) -> FlutterStandardTypedData? {
    guard let cgImage = CGDisplayCreateImage(displayId) else { return nil }

    let sourceWidth = cgImage.width
    let sourceHeight = cgImage.height
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }

    let targetWidth = min(maxWidth, sourceWidth)
    let scale = Double(targetWidth) / Double(sourceWidth)
    let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    guard let scaledImage = context.makeImage() else { return nil }

    let bitmapRep = NSBitmapImageRep(cgImage: scaledImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: pngData)
  }
}
