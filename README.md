# Gang Chat Client

Flutter UI with text auth/session flows and the first-party `gang_video`
native video plugin.

## Stream Layout

The client talks to independent TCP streams:

- `TextStreamClient` connects to the central text server on `:21117`.
- `RelayClient` connects to the video/screen-share relay on `:21119`.

## Native Video

The video encode/decode path lives in the Flutter plugin package:

```text
client/packages/gang_video
```

macOS uses Swift + ScreenCaptureKit/VideoToolbox. Windows uses C++20 +
Windows.Graphics.Capture, D3D11, and Media Foundation H.264 MFTs. The old
Rust bridge is gone.

## Smoke Test

With the unified server running:

```bash
cd ../server
cargo run -p app -- \
  --text-bind 127.0.0.1:21117 \
  --audio-bind 127.0.0.1:21118 \
  --video-bind 127.0.0.1:21119
```

Then:

```bash
cd client
flutter run -d macos
# or
flutter run -d windows
```
