# 解耦后的模块化开发指南

本文档说明当前客户端解耦后的目录职责、依赖方向和后续开发流程。目标是让 v2 UI 可以复用现有登录、房间、消息、设置、Live 和文件能力，而不把业务逻辑重新写进 widget。

## 核心原则

1. UI 只负责展示、输入和页面编排。
2. 业务规则、状态 patch、展示文案和 action gate 优先放进 `lib/src/app`。
3. 平台能力和插件 SDK 调用放在 adapter 层，例如 `lib/src/shell`、`lib/src/live`。
4. 可复用视觉组件放进 `lib/src/ui`，不要依赖具体业务 controller。
5. v2 页面先调用已有 app controller/service，不复制旧 UI 页面里的业务逻辑。
6. 每个可复用逻辑模块都要有聚焦测试，跨模块改动再跑全量 `flutter analyze` 和 `flutter test --no-pub`。

## 目录职责

### `lib/src/app`

应用逻辑层。这里放纯业务规则、状态 reducer/patch、展示映射、controller 和 app session 上下文。

适合放这里的内容：

- 表单校验和 submit draft，例如 `account_forms.dart`、`room_forms.dart`。
- 展示文案和 UI 无关的 display helper，例如 `room_display.dart`、`file_display.dart`、`live_display.dart`。
- 可测试的状态变更，例如 `home_shell_state.dart`、`settings_shell_state.dart`、`audio_device_state.dart`。
- controller，例如 `messages_controller.dart`、`rooms_controller.dart`、`settings_controller.dart`。
- app 可见的协议/抽象，例如 `AudioDeviceStore`。

不要放这里：

- `BuildContext`、`Widget`、`Color`、`IconData`。
- `package:flutter`、`file_selector`、`flutter_secure_storage`、`window_manager` 等 UI 或平台插件。
- 页面弹窗、Navigator、toast 展示、布局代码。

当前约束可以用这个命令审计：

```sh
rg -n "package:flutter|dart:ui|file_selector|livekit_client|flutter_webrtc|window_manager|BuildContext|Widget|Color|IconData|XFile|Clipboard|Navigator|showDialog" lib/src/app
```

正常结果应该为空。

### `lib/src/shell`

应用壳和平台 adapter 层。这里放 Flutter app 入口、登录壳、窗口控制、剪贴板、文件选择、secure storage 这类平台边界。

典型文件：

- `gang_app.dart`：MaterialApp、AuthGate、v1/v2 路由入口。
- `login_page.dart`：登录 UI，复用真实 auth session。
- `clipboard_service.dart`：剪贴板读写和 Windows clipboard file path。
- `file_selection_service.dart`：文件选择、保存位置、`SelectedFile`、`FileTypeGroup`。
- `secure_audio_device_store.dart`：`AudioDeviceStore` 的真实 secure storage 实现。

规则：

- shell 可以 import Flutter 和插件。
- shell 提供可注入 service，feature UI 通过构造参数接收。
- 不要把业务状态判断写进 shell service；shell service 只包平台能力。

### `lib/src/ui`

可复用 UI kit 和展示 adapter 层。这里放 button、input、composer、navigation、sidebar、avatar、file icon、gender mark 等组件。

规则：

- 组件必须尽量业务无关，通过参数传入数据和 callback。
- 这里可以使用 Flutter widget，但不要直接调用 API controller。
- 如果组件需要把平台/SDK 类型转成 app 逻辑输入，做成薄 adapter，例如 `sticker_upload_adapter.dart`。
- showcase 只用于验证 UI kit 行为，不承载主业务逻辑。

### `lib/src/home`

v1 主界面 UI。现在已经拆成：

- `home_page.dart`：页面总编排、服务注入、生命周期、实时事件连接。
- `home_sidebar.dart`：侧栏。
- `home_chat.dart`：聊天区域。
- `home_live.dart`：Live panel 和 screen share UI。
- `home_room_dialogs.dart`：房间信息、管理、成员、贴纸等弹窗。

规则：

- 可以保留 `showDialog`、`Navigator`、布局和 widget 状态。
- 业务判断应调用 `lib/src/app` helper/controller。
- 文件选择、剪贴板等平台能力必须通过 `ClipboardService` / `FileSelectionService` 注入。
- 不要在这里直接 import `file_selector` 或 `livekit_client`。

### `lib/src/settings`

v1 设置页 UI。现在已经拆成：

- `settings_page.dart`：页面编排和 controller 调用。
- `settings_components.dart`：设置页通用局部组件。
- `settings_profile_widgets.dart`：账号/资料 UI。
- `settings_stickers.dart`：贴纸管理 UI。
- `settings_audio_widgets.dart`：音频设置 UI。

规则：

- 账号、资料、贴纸和音频的状态 patch、校验、展示 copy 放在 `lib/src/app`。
- LiveKit 音频设备类型不要出现在 settings UI；使用 `AudioDeviceInfo`。
- 文件、保存、剪贴板必须走 shell service。

### `lib/src/live`

LiveKit 和 WebRTC adapter 层。这里可以直接接触 LiveKit SDK，但对 Home/Settings 暴露稳定的小接口。

典型文件：

- `live_session.dart`：LiveKit session wrapper、screen source、video track snapshot。
- `audio_device_service.dart`：LiveKit hardware device adapter。
- `audio_device_restorer.dart`：恢复已存储音频设备。
- `audio_test_service.dart`：测试音频输入/输出生命周期。
- `live_video_track_view.dart`：LiveKit video renderer wrapper。

规则：

- SDK 具体类型优先留在 live adapter 内。
- UI 要渲染视频时使用 `LiveVideoTrackView`，不要直接使用 `lk.VideoTrackRenderer`。
- 可纯化的筛选、状态和 copy 继续放到 `lib/src/app/live_display.dart`。

### `lib/src/v2`

v2 UI 入口。当前主界面还未正式迁移，后续从这里开始接入新的页面。

规则：

- 登录继续走 `GangApp` / `_AuthGate` / `AuthSessionController` 的真实链路。
- 登录后页面通过 `AuthenticatedAppContext` 创建或接收 `AuthenticatedAppServices`。
- 不要复制 v1 Home/Settings 的业务逻辑；优先复用 `lib/src/app` controller 和 helper。
- 新 UI 组件优先沉淀到 `lib/src/ui`，不要只为 v2 写一份重复组件。

### `lib/src/protocol`

网络协议和模型层。API client、model、stream client 等保持在这里或相邻低层目录。

规则：

- app controller 可以调用 protocol client。
- UI 不应该直接拼请求 body；通过 app controller 或已有 API method 进入。
- 新接口先补 protocol 方法，再由 app controller 封装成 UI 友好的 action。

## 依赖方向

推荐依赖方向：

```text
protocol/config
  -> app
  -> shell/live adapters
  -> feature UI (home/settings/v2)
  -> reusable ui
```

实际开发时按下面约束判断：

- `app` 不依赖 Flutter UI 和平台插件。
- `shell` 和 `live` 可以依赖插件，但要把插件类型藏在 service/adapter 内。
- `home/settings/v2` 可以依赖 Flutter widget，但业务逻辑要调用 `app`。
- `ui` 只做可复用 widget 和展示 adapter，不调用业务 API。

## 新功能开发流程

### 1. 先定义业务能力

先问清楚这个功能是否已有 controller/helper：

- 房间：`RoomsController`、`room_forms.dart`、`room_display.dart`。
- 消息：`MessagesController`、`message_display.dart`。
- 文件：`FileDownloadsController`、`file_display.dart`。
- Live：`LiveController`、`LiveSessionController`、`live_display.dart`。
- 设置：`SettingsController`、`settings_shell_state.dart`。
- 贴纸：`StickerPacksController`、`sticker_management.dart`、`sticker_uploads.dart`。

如果没有，先在 `lib/src/app` 加最小可测试逻辑。

### 2. 再接平台或 SDK 能力

如果需要系统能力：

- 文件选择/保存：扩展 `FileSelectionService`。
- 剪贴板：扩展 `ClipboardService`。
- secure storage：通过 app 协议 + shell 实现。
- LiveKit/WebRTC：放到 `lib/src/live` adapter。
- 窗口控制：放到 `DesktopWindowController` 或 shell 层。

不要在页面里直接调用插件 API。

### 3. 最后写 UI

UI 页面只做：

- 读取当前 state。
- 调用 controller/service。
- 调用 app helper 生成展示文案、按钮状态、列表状态。
- 展示 loading/error/empty/result。
- 管理必要的 text controller、focus node、弹窗生命周期。

复杂 widget 拆分优先级：

1. 可跨页面复用的组件放 `lib/src/ui`。
2. 只属于一个 feature 的大块 UI 放对应 feature part 文件。
3. 可测试状态逻辑抽到 `lib/src/app`。

## v2 迁移建议

v2 不需要一次重写所有业务。建议顺序：

1. 复用当前登录和缓存链路，保持 `useV2` 入口。
2. 用 `AuthenticatedAppServices` 接入房间列表和当前用户。
3. 接入消息列表和发送消息，复用 `MessagesController`。
4. 接入文件发送/下载，复用 `SelectedFile` 和 `FileDownloadsController`。
5. 接入 settings 的账号、贴纸、音频模块，复用 `SettingsController`。
6. 最后接 Live，因为 Live 涉及 SDK adapter、窗口控制和视频渲染。

每迁移一块，都保持 v1 可用，不要为了 v2 改坏 v1 controller contract。

## 测试策略

### app 逻辑测试

每个新增 app helper/controller 都应有测试：

- 表单校验：输入、trim、无变更、错误文案。
- reducer/patch：busy、error、notice、selection、stale result。
- display helper：fallback、label、排序、过滤。
- controller：API 调用顺序、pending state、失败恢复。

### UI widget 测试

适合验证：

- UI kit 布局和交互。
- v2 入口是否识别。
- 嵌入式 settings/home 的关键 affordance 是否存在。
- 输入框、composer、sidebar 这类容易回归的布局行为。

### 推荐命令

小改动先跑聚焦验证，例如：

```sh
flutter analyze lib/src/app/room_forms.dart test/room_forms_test.dart
flutter test --no-pub test/room_forms_test.dart
```

跨层或提交前跑全量：

```sh
flutter analyze
flutter test --no-pub
```

## 提交前检查清单

- `lib/src/app` 没有 Flutter/plugin/UI 依赖。
- UI 页面没有直接 import `file_selector`、`flutter_secure_storage`、`livekit_client` renderer。
- 新业务逻辑有 app 层测试。
- 新平台能力通过 shell/live adapter 注入。
- v1 原流程没有被 v2 改动破坏。
- `flutter analyze` 通过。
- 涉及多模块时 `flutter test --no-pub` 通过。

## 常见反模式

- 在 widget 里拼 API request body。
- 在 widget 里维护一套可复用的搜索、排序、权限判断。
- 在 v2 里复制 v1 Home/Settings 的业务代码。
- 在 `lib/src/app` import Flutter、插件或 SDK renderer。
- 为一个业务页面写只能在该页面使用的通用按钮/input。
- 让 shell service 返回第三方插件类型，导致 UI 层继续被插件绑定。

## 推荐新增文件命名

- app 纯逻辑：`<domain>_forms.dart`、`<domain>_display.dart`、`<domain>_state.dart`。
- app controller：`<domain>_controller.dart` 或复用已有 controller。
- shell service：`<capability>_service.dart`。
- live adapter：`audio_*`、`live_*`，保持 SDK 细节在 adapter 内。
- feature UI part：`home_<section>.dart`、`settings_<section>.dart`。
- ui 组件：直接用通用名，例如 `button.dart`、`input.dart`、`navigation.dart`。

## 当前稳定边界

当前可以依赖的边界：

- `AuthenticatedAppContext`：登录后的 API/token/config/sticker store 上下文。
- `AuthenticatedAppServices`：登录后的 controller 集合。
- `AuthSessionController`：真实登录、缓存和登出状态。
- `ClipboardService`、`FileSelectionService`、`SecureAudioDeviceStore`：平台能力 adapter。
- `LiveSessionController`、`LiveAudioDeviceService`、`AudioTestService`：Live/audio adapter。
- `lib/src/ui` 组件：v1、v2、showcase 都应优先复用。
