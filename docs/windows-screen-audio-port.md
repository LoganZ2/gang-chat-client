# Windows 屏幕共享音频独立轨道移植指南

## 背景

macOS 已实现屏幕共享音频作为独立 `TrackSource.screenShareAudio` 轨道，通过第二个 `RTCPeerConnectionFactory` + 自定义 ADM + 第二个隐藏 LiveKit 参与者发布。Windows 端需要照搬同一架构。

**核心问题（两端相同）**：WebRTC 的一个 `RTCPeerConnectionFactory` 拥有一个 `AudioState`，其单一 ADM 采集会被 fan-out 到该工厂所有活跃的 `AudioSendStream`。如果用自定义 `RTCAudioSource` 在主工厂上推屏幕音频帧，屏幕音频线程和麦克风采集线程会同时进入同一个 `AudioSendStream` 的 `audio_capture_race_checker_`，触发 `audio_send_stream.cc:393` 的 `RTC_CHECK` 崩溃。

**解法（两端相同）**：给屏幕音频一个独立的工厂 + 独立的 ADM，让屏幕音频走 `RecordedDataIsAvailable` 序列化路径，彻底不与麦克风共享 `AudioState`。

---

## 架构总览

```
┌─ 主房间 (factory-1, 麦克风 ADM) ────────────────────────────┐
│  RTCPeerConnectionFactory (默认 ADM = CoreAudio/WASAPI 麦克风)  │
│  ├─ LocalParticipant 麦克风音频轨道                            │
│  └─ LocalParticipant 屏幕共享视频轨道                          │
└────────────────────────────────────────────────────────────┘
┌─ 辅助房间 (factory-2, 自定义屏幕音频 ADM) ──────────────────┐
│  RTCPeerConnectionFactory (ADM = ScreenAudioDevice)           │
│  └─ 隐藏参与者 <userID>--screen-audio                         │
│      └─ LocalAudioTrack (screenShareAudio)                    │
└────────────────────────────────────────────────────────────┘
```

**数据流（Windows）**：
```
WASAPI loopback capture → ScreenAudioDevice::OnRecordedData
  → factory-2 的 AudioSendStream（序列化，无竞争）
  → 辅助房间发布 → SFU → 接收方
```

---

## 已通用（无需改动）

以下部分是跨平台的，Windows 直接复用：

### Dart 层
- `lib/src/live/screen_audio_publisher.dart` — 完整的辅助房间发布器，通过 `peerConnectionCreate` 注入工厂-2
- `lib/src/live/live_session.dart` — `setScreenShareEnabled` 先启视频，后 `unawaited()` 启辅助发布器；`screenShareVolume` 独立音量；自回声抑制（自己的 aux 轨道 volume=0）；`--screen-audio` 身份过滤
- `third_party/flutter_webrtc/lib/src/native/factory_impl.dart` — `createScreenAudioPeerConnection()` 和 `createScreenAudioTrack()` Dart wrapper
- `third_party/livekit_client/` — vendored，`Engine` 已 export

### Server
- `POST /rooms/:room_id/live/screen-audio-token` — 已部署（commit `81121c4`），返回 `<userID>--screen-audio` 身份的 publish-only token

### flutter_webrtc Dart wrapper
- `createScreenAudioPeerConnection` / `createScreenAudioTrack` — 平台无关，通过 method channel 调用 native

---

## Windows 需要实现的部分

### 1. 自定义 AudioDeviceModule (C++)

**对应 macOS**：`FlutterScreenAudioDevice.h/.m` (ObjC `RTCAudioDevice`)

**Windows 需要做**：实现一个自定义 `RTCAudioDevice` 子类（C++）。

⚠️ **关键差异**：Windows 的 `libwebrtc::RTCAudioDevice` 接口（`third_party/libwebrtc/include/rtc_audio_device.h`）与 macOS 的 ObjC `RTCAudioDevice` 协议**不同**。Windows 的 `RTCAudioDevice` 只有设备枚举方法（`PlayoutDevices()`, `RecordingDevices()`, `SetRecordingDevice()` 等），**没有** `deliverRecordedData` 回调。

这意味着 Windows 端不能像 macOS 那样通过 `RTCAudioDeviceDelegate.deliverRecordedData` 投递音频。需要走 libwebrtc 底层的 `AudioDeviceModule` C++ 接口。

**推荐方案**：

查看 `libwebrtc` 预编译库（`third_party/libwebrtc/`）是否暴露了底层 `AudioDeviceModule` 接口。如果 `LibWebRTC::CreateRTCPeerConnectionFactory()` 不接受自定义 ADM 参数（当前签名是 `CreateRTCPeerConnectionFactory()` 无参），则需要：

**方案 A（推荐）**：修改 `flutter_webrtc` 的 C++ wrapper，在 `LibWebRTC` 层面增加一个 `CreateRTCPeerConnectionFactory(scoped_refptr<RTCAudioDevice> audio_device)` 重载，允许传入自定义 ADM。

**方案 B**：如果 libwebrtc 预编译库不暴露这个能力，需要重新编译 libwebrtc，在 `RTCPeerConnectionFactoryImpl` 中增加接受自定义 `AudioDeviceModule` 的构造路径。

**自定义 ADM 需要实现的行为**：
```
- 录制端：
  - 声明 48kHz mono int16（WebRTC FineAudioBuffer 会处理重采样）
  - WASAPI loopback 采集线程喂帧进来时，缓存在一个串行队列里
  - WebRTC 的音频线程调用 Record() / RecordedDataIsAvailable() 时，
    从队列取出 PCM 帧返回
  - 关键：投递必须在单一串行队列上完成，保证不会并发进入
    AudioSendStream 的 capture race checker
- 播放端：
  - 返回静音（屏幕音频参与者是 publish-only，不播放）
```

**参考 macOS 实现**（`FlutterScreenAudioDevice.m`）：
- 48kHz mono int16 输出
- SCK 采集 48kHz stereo，在 `deliverSampleBufferOnQueue:` 中线性重采样降混为 mono
- 单一 serial dispatch queue (`com.gangchat.screenaudio.adm`) 保证序列化投递
- playout 端全部返回 YES/silence（publish-only）

### 2. WASAPI Loopback 采集器 (C++)

**对应 macOS**：`FlutterScreenCaptureKitCapturer.m` 中的 SCK 音频采集

**Windows 已有代码**：`common/cpp/src/flutter_screen_audio_capture.cc` 已有完整的 WASAPI loopback 采集实现，包括：
- Process Loopback（按进程 ID 采集，类似 macOS 的 `excludesCurrentProcessAudio`）
- System Loopback fallback（回退到系统默认渲染端点）
- 48kHz stereo 16-bit PCM
- 10ms chunk 分发

**但当前代码把帧推给 `RTCAudioSource::CaptureFrame()`**，这正是竞争者。需要改为推给自定义 ADM 的录制队列。

**改动点**：
```cpp
// 当前（有问题）：
audio_source_->CaptureFrame(chunk, kBitsPerSample, kSampleRate,
                            kChannels, chunk_frames);

// 改为：
ScreenAudioDevice::Instance()->EnqueueAudioData(
    chunk, kBitsPerSample, kSampleRate, kChannels, chunk_frames);
```

### 3. 第二个 RTCPeerConnectionFactory (C++)

**对应 macOS**：`FlutterWebRTCPlugin.m` 中的 `screenAudioPeerConnectionFactory` getter

**Windows 实现位置**：`common/cpp/src/flutter_webrtc_base.cc` 或 `common/cpp/src/flutter_webrtc.cc`

**需要做**：
```cpp
// 在 FlutterWebRTCBase 中增加：
scoped_refptr<RTCPeerConnectionFactory> screen_audio_factory_;

scoped_refptr<RTCPeerConnectionFactory> screen_audio_factory() {
  if (screen_audio_factory_) return screen_audio_factory_;
  screen_audio_factory_ = LibWebRTC::CreateRTCPeerConnectionFactory(
      /* audio_device = */ ScreenAudioDevice::Instance());
  screen_audio_factory_->Initialize();
  return screen_audio_factory_;
}
```

### 4. Method Channel Handlers (C++)

**对应 macOS**：`FlutterWebRTCPlugin.m` 中的 `screenAudioCreatePeerConnection` 和 `screenAudioCreateTrack`

**Windows 实现位置**：`common/cpp/src/flutter_webrtc.cc` 的 `HandleMethodCall`

**需要做**：增加两个 handler：

```cpp
// screenAudioCreatePeerConnection:
//   在 screen_audio_factory() 上创建 PC，注册到 peerconnections_ map
//   返回 {"peerConnectionId": uuid}

// screenAudioCreateTrack:
//   在 screen_audio_factory() 上创建 audio source + track
//   注册到 local_tracks_ map
//   返回 {"id": trackId, "streamId": streamId, "kind": "audio", ...}
```

**关键细节**（macOS 踩过的坑）：
- 返回的 track map 必须用 `id` 键（不是 `trackId`），因为 Dart 侧 `MediaStreamTrackNative.fromMap` 读 `map['id']`
- 返回的 map 类型必须是 `Map<Object?, Object?>` 兼容的，Dart 侧用 `MediaStreamTrackNative.fromMap(response, 'local')` 解析

### 5. getDisplayMedia 改动 (C++)

**对应 macOS**：`FlutterRTCDesktopCapturer.m` 中的 `getDisplayMedia` — SCK 始终采集音频，音频转发到 `FlutterScreenAudioDevice`，MediaStream 是纯视频

**Windows 实现位置**：`common/cpp/src/flutter_screen_capture.cc` 的 `GetDisplayMedia`

**需要做**：
- 屏幕共享视频照常走 `RTCDesktopCapturer`
- 音频不再创建 `RTCAudioSource(kCustom)` 轨道加到 MediaStream
- 改为启动 WASAPI loopback 采集，帧推给自定义 ADM
- MediaStream 返回纯视频（音频由辅助发布器独立处理）
- 删除 `FLUTTER_WEBRTC_ENABLE_UNSAFE_WINDOWS_SCREEN_AUDIO` 编译开关和相关的 `RTCAudioSource::kCustom` 路径

### 6. 删除 Windows 禁用门 (Dart)

**文件**：`lib/src/live/live_session.dart`

**当前代码**：
```dart
bool shouldRequestScreenShareAudio({
  required String? sourceId,
  required bool isDesktopSourcePickerPlatform,
  required bool isWindowsDesktop,
}) {
  if (isDesktopSourcePickerPlatform && isWindowsDesktop) {
    return false;  // ← 删掉这个
  }
  return true;
}
```

**改为**：直接 `return true;`，或在 Windows native 实现完成后删掉 `isWindowsDesktop` 参数。

同时把 `setScreenShareEnabled` 中的 `captureScreenAudio: false`（当前硬编码为 false 以避免 factory-1 创建音频轨道）改为 `captureScreenAudio: false`（保持不变 — 即使 Windows native 实现了，`getDisplayMedia` 也不应在 factory-1 上创建音频轨道；音频走 factory-2 的辅助发布器）。这一条**不用改**。

### 7. CMakeLists.txt 更新

**文件**：`third_party/flutter_webrtc/windows/CMakeLists.txt`

需要把新的 C++ 源文件（自定义 ADM、修改后的 screen audio capture）加入编译列表。

---

## 实现顺序

1. **先验证 `libwebrtc` 是否支持自定义 ADM 注入**
   - 检查 `LibWebRTC::CreateRTCPeerConnectionFactory()` 是否有接受 `RTCAudioDevice*` 的重载
   - 如果没有，检查 `RTCPeerConnectionFactory` 是否有 `SetAudioDevice()` 方法
   - 如果都没有，需要修改 `libwebrtc` 源码或寻找其他注入方式 — **这是决定整体可行性的关键前置问题**

2. **实现自定义 ADM**（`ScreenAudioDevice` C++ 类）
   - 录制端：串行队列缓存 WASAPI 帧，WebRTC 调用时返回
   - 播放端：静音

3. **改造 WASAPI 采集器**
   - 把 `flutter_screen_audio_capture.cc` 的 `PushFrames` / `PushSilentFrames` 改为推给 `ScreenAudioDevice` 而非 `RTCAudioSource::CaptureFrame()`

4. **增加 method channel handlers**
   - `screenAudioCreatePeerConnection` / `screenAudioCreateTrack`

5. **改造 getDisplayMedia**
   - 删除 `RTCAudioSource::kCustom` 路径
   - 启动 WASAPI loopback → 推给 ADM
   - MediaStream 纯视频

6. **删除 Windows 禁用门**（Dart `shouldRequestScreenShareAudio`）

7. **编译验证**：`flutter build windows --debug`

8. **运行时验证**：
   - 整屏共享 + 播放声音 → 接收方听到
   - 窗口共享 + 播放声音 → 接收方听到（Windows 的 WASAPI process loopback 支持窗口级音频）
   - 麦克风和屏幕音频音量独立调节
   - 无 `audio_send_stream.cc` 崩溃
   - 无自回声

---

## macOS 实现参考文件

| 文件 | 作用 |
|------|------|
| `macos/Classes/FlutterScreenAudioDevice.h/.m` | 自定义 ADM (ObjC `RTCAudioDevice`)，48kHz mono，serial queue 投递 |
| `macos/Classes/FlutterScreenCaptureKitCapturer.h/.m` | SCK 采集器，音频转发到 `FlutterScreenAudioDevice`；含 `startAudioOnlyCaptureForWindowSourceId:` 窗口音频采集 |
| `macos/Classes/FlutterWebRTCPlugin.m` | `screenAudioPeerConnectionFactory` getter + `screenAudioCreatePeerConnection` / `screenAudioCreateTrack` handlers |
| `macos/Classes/FlutterRTCDesktopCapturer.m` | `getDisplayMedia`：SCK 始终采集音频，MediaStream 纯视频；窗口共享走 audio-only SCK |
| `lib/src/native/factory_impl.dart` | `createScreenAudioPeerConnection()` / `createScreenAudioTrack()` Dart wrapper（跨平台复用） |

---

## 关键约束

1. **不能在 factory-1 上创建屏幕音频轨道** — `setScreenShareEnabled` 必须传 `captureScreenAudio: false`（已是如此），音频走 factory-2 的辅助发布器
2. **身份分隔符用 `--` 不是 `#`** — `#` 是 URL fragment，会被 LiveKit WebSocket 截断导致身份碰撞
3. **辅助 token 按需获取** — `POST /rooms/:room_id/live/screen-audio-token`，token 10 分钟有效
4. **辅助参与者 `canSubscribe=false`** — publish-only，不接收其他人的轨道，避免回声
5. **自定义 ADM 必须序列化投递** — 不能从 WASAPI 线程直接调 WebRTC 音频回调，必须经过 serial queue，否则会再次触发 RaceChecker
6. **`excludesCurrentProcessAudio` 等价** — Windows 的 process loopback 用 `PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE` 排除自身进程（已有代码），或系统 loopback 后在 ADM 中过滤
7. **音量独立** — `screenShareVolume` 只影响 `screenShareAudio` 来源的轨道，不影响麦克风（`outputVolume`）或音乐盒（`musicBoxVolume`）

---

## 风险

- **`libwebrtc` 预编译库可能不支持自定义 ADM 注入** — 这是最大的不确定性。macOS 的 ObjC `RTCAudioFactory` 暴露了 `initWithEncoderFactory:decoderFactory:audioDevice:`，但 Windows 的 C++ `LibWebRTC::CreateRTCPeerConnectionFactory()` 无参。如果底层不支持，需要重新编译 libwebrtc 或找替代注入方式。
- **WASAPI process loopback 兼容性** — 需要 Windows 10 2004+。当前代码已有 system loopback fallback。
- **窗口级音频** — Windows 的 WASAPI process loopback 按进程 ID 采集，窗口共享时需要解析窗口→进程 ID（当前代码已有 `ResolveWindowProcessId`）。
