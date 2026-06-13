import Cocoa
import CoreAudio
import CoreGraphics
import FlutterMacOS
import WebRTC

private let loginWindowSize = NSSize(width: 430, height: 256)
private let resizeCursorEdgeWidth: CGFloat = 8
// Logical height of the v2 Flutter title bar. The native traffic lights are
// vertically centered within this band. Keep in sync with `_homeTitleBarHeight`
// in lib/src/v2/home_shell_title_bar.dart.
private let v2TitleBarHeight: CGFloat = 44
private let screenThumbnailChannel = "gang_chat/screen_thumbnail"
private let clipboardChannel = "gang_chat/clipboard"
private let fileDropChannel = "gang_chat/file_drop"
private let audioDevicesChannel = "gang_chat/audio_devices"
private let appBackground = NSColor(
  red: CGFloat(0x14) / 255.0,
  green: CGFloat(0x17) / 255.0,
  blue: CGFloat(0x1D) / 255.0,
  alpha: 1
)

class MainFlutterWindow: NSWindow {
  private var resizeCursorActive = false
  private var fileDropMethodChannel: FlutterMethodChannel?
  private var audioDevicesMethodChannel: FlutterMethodChannel?
  private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?
  private lazy var audioDeviceFactory = RTCPeerConnectionFactory()

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
    registerClipboardChannel(flutterViewController)
    registerAudioDevicesChannel(flutterViewController)
    installFileDropTarget(flutterViewController)
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
    removeDefaultInputListener()
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

  // Exposes the system's current default audio input device on
  // `gang_chat/audio_devices`. flutter_webrtc's CoreAudio ADM never surfaces a
  // synthetic "default" entry on macOS (unlike Windows), so the Dart side has no
  // way to tell which enumerated device the OS currently treats as the default
  // microphone. We answer that here using WebRTC's own RTCIODevice list, whose
  // `deviceId` strings are the exact ones flutter_webrtc reports through
  // enumerateDevices — so the value lines up with no UID translation. A CoreAudio
  // property listener pushes `defaultInputDeviceChanged` whenever the user
  // switches the default input in System Settings, letting the picker follow it
  // live.
  //
  // Methods: `getDefaultInputDeviceId` -> String? (deviceId of the default mic).
  // Events: `defaultInputDeviceChanged` with argument String? (the new deviceId).
  private func registerAudioDevicesChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: audioDevicesChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    audioDevicesMethodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getDefaultInputDeviceId":
        result(self?.defaultInputDeviceId())
      case "startListening":
        self?.installDefaultInputListener()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // RTCAudioDeviceModule.inputDevices is the exact array flutter_webrtc builds
  // its enumerateDevices() result from (see FlutterRTCMediaStream's getSources),
  // so the deviceId of whichever entry is flagged `isDefault` matches the
  // picker's device ids with no UID translation. We read it through our own
  // factory rather than flutter_webrtc's private singleton; both link the same
  // WebRTC-SDK pod version, so the deviceId derivation is identical.
  private func defaultInputDeviceId() -> String? {
    let adm = audioDeviceFactory.audioDeviceModule
    let inputs = adm.inputDevices
    if let match = inputs.first(where: { $0.isDefault }) {
      return match.deviceId
    }
    return adm.inputDevice.deviceId
  }

  private func installDefaultInputListener() {
    guard defaultInputListenerBlock == nil else { return }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self = self else { return }
      self.audioDevicesMethodChannel?.invokeMethod(
        "defaultInputDeviceChanged",
        arguments: self.defaultInputDeviceId()
      )
    }
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      block
    )
    if status == noErr {
      defaultInputListenerBlock = block
    }
  }

  private func removeDefaultInputListener() {
    guard let block = defaultInputListenerBlock else { return }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectRemovePropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      block
    )
    defaultInputListenerBlock = nil
  }

  // Mirrors the Windows runner's `gang_chat/clipboard` channel so paste-to-send
  // works on macOS: `readFilePaths` returns paths of files copied in Finder,
  // `readImageFile` returns a screenshot/copied image re-encoded as PNG.
  private func registerClipboardChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: clipboardChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "readFilePaths":
        result(self.readClipboardFilePaths())
      case "readImageFile":
        result(self.readClipboardImageFile())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readClipboardFilePaths() -> [String] {
    let pasteboard = NSPasteboard.general
    guard
      let urls = pasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL]
    else {
      return []
    }
    return urls.filter { $0.isFileURL }.map { $0.path }
  }

  private func readClipboardImageFile() -> [String: Any]? {
    let pasteboard = NSPasteboard.general

    // Prefer a PNG/TIFF blob already on the pasteboard; fall back to decoding
    // any NSImage representation (e.g. a screenshot) and re-encoding to PNG so
    // the Dart side always receives `image/png` like the Windows runner.
    var pngData: Data?
    if let png = pasteboard.data(forType: .png) {
      pngData = png
    } else if let tiff = pasteboard.data(forType: .tiff),
      let rep = NSBitmapImageRep(data: tiff) {
      pngData = rep.representation(using: .png, properties: [:])
    } else if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
      let image = images.first,
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) {
      pngData = rep.representation(using: .png, properties: [:])
    }

    guard let data = pngData, !data.isEmpty else { return nil }
    return [
      "bytes": FlutterStandardTypedData(bytes: data),
      "filename": "clipboard-image.png",
      "mime_type": "image/png",
    ]
  }

  // Adds a transparent overlay over the Flutter view that accepts file drags
  // and forwards them on `gang_chat/file_drop` as `dropFiles {paths,x,y}`,
  // matching the Windows runner. The overlay is flipped (origin top-left) so
  // its drop coordinates already line up with Flutter's logical coordinate
  // space, and it passes hit-testing through so it never steals mouse events.
  private func installFileDropTarget(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: fileDropChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    fileDropMethodChannel = channel

    let contentView = flutterViewController.view
    let dropView = FileDropView()
    dropView.onDrop = { [weak self] paths, point in
      guard let self = self, !paths.isEmpty else { return }
      self.fileDropMethodChannel?.invokeMethod(
        "dropFiles",
        arguments: [
          "paths": paths,
          "x": Double(point.x),
          "y": Double(point.y),
        ]
      )
    }
    dropView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(dropView)
    NSLayoutConstraint.activate([
      dropView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      dropView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      dropView.topAnchor.constraint(equalTo: contentView.topAnchor),
      dropView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
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

/// Transparent drag-and-drop overlay for the Flutter view. Accepts file drags
/// and reports dropped paths plus the drop point in Flutter logical coordinates
/// (origin top-left). `isFlipped` keeps the coordinate system aligned with
/// Flutter, and `hitTest` returns nil so the view never intercepts clicks.
final class FileDropView: NSView {
  var onDrop: (([String], CGPoint) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.fileURL])
  }

  override var isFlipped: Bool { true }

  // Pass all mouse events through to the Flutter view beneath us; this view
  // only exists to receive drags.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return hasFileURLs(sender) ? .copy : []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return hasFileURLs(sender) ? .copy : []
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return hasFileURLs(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = filePaths(sender)
    guard !paths.isEmpty else { return false }
    let point = convert(sender.draggingLocation, from: nil)
    onDrop?(paths, point)
    return true
  }

  private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
    return !filePaths(sender).isEmpty
  }

  private func filePaths(_ sender: NSDraggingInfo) -> [String] {
    guard
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
      ) as? [URL]
    else {
      return []
    }
    return urls.filter { $0.isFileURL }.map { $0.path }
  }
}
