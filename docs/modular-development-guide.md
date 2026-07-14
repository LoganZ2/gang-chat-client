# 解耦后的模块化开发指南

本文档说明当前客户端解耦后的目录职责、依赖方向和后续开发流程。目标是让 v2 UI 可以复用现有登录、房间、消息、设置、Live 和文件能力，而不把业务逻辑重新写进 widget。

## 核心原则

1. UI 只负责展示、输入和页面编排。
2. 业务规则、状态 patch、展示文案和 action gate 优先放进 `lib/src/app`。
3. 平台能力和插件 SDK 调用放在 adapter 层，例如 `lib/src/shell`、`lib/src/live`。
4. 可复用视觉组件放进 `lib/src/ui`，不要依赖具体业务 controller。
5. v2 页面先调用已有 app controller/service，不复制旧 UI 页面里的业务逻辑。
6. 每个可复用逻辑模块都要有聚焦测试；测试按层级和模块分类存放，跨模块改动再跑全量 `flutter analyze` 和 `flutter test --no-pub`。

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

### 测试目录与分类

客户端测试按“测试层级 + 被测模块”两级分类，不再把所有测试平铺在 `test/` 根目录：

```text
test/
  unit/
    app/          # 业务规则、状态、controller、display/form helper
    protocol/     # API client、协议模型、URL 和序列化规则
    live/         # LiveKit/WebRTC adapter 的可隔离逻辑
    shell/        # 剪贴板、更新、持久化等平台边界的可隔离逻辑
  widget/
    ui/           # 可复用 UI kit
    home/         # 主界面和聊天/Live feature widget
    settings/     # 设置页 feature widget
    shell/        # 应用壳、登录入口和桌面事件 widget
      gang_app_shell_test.dart
      gang_app_shell_test_parts/ # 共享同一测试 library 的分类用例
integration_test/
  *_probe_test.dart # 依赖真实系统、硬件或插件运行时的人工/平台探针
```

分类规则：

- 不需要创建 Flutter widget 树的测试放 `test/unit/<module>/`。
- 需要 `testWidgets`、布局、焦点、手势或渲染验证的测试放 `test/widget/<module>/`。
- 只有真实 Windows/macOS、音频设备、摄像头或插件运行时才能验证的场景放 `integration_test/`。
- `integration_test/*_probe_test.dart` 不属于默认快速回归套件，必须在目标平台显式运行并记录运行环境。
- 测试文件名与被测文件或能力对应，统一使用 `<subject>_test.dart`；平台探针使用 `<subject>_probe_test.dart`。
- 同一能力同时有纯逻辑和 widget 行为时分别建测试，不要为了少一个文件把 widget 测试混入 `unit/`。
- 通用 fake、fixture 或 matcher 达到两个以上使用方时，再提取到相邻的 `test_support/`；单个测试专用数据留在原文件，避免形成难以追踪的全局测试工具箱。
- 单个 widget 测试库过大且大量依赖共享私有 fake 时，可以保留一个可发现的 `*_test.dart` 入口，并把领域用例拆到相邻的 `*_test_parts/`。part 文件使用 `*_tests.dart`，避免被 Flutter 当作独立测试重复发现；入口只负责导入、注册分类用例和保存共享 fixture。当前应用壳采用 `gang_app_shell_test.dart` + `gang_app_shell_test_parts/`。

### 单元测试

每个新增 app helper/controller 都应有测试：

- 表单校验：输入、trim、无变更、错误文案。
- reducer/patch：busy、error、notice、selection、stale result。
- display helper：fallback、label、排序、过滤。
- controller：API 调用顺序、pending state、失败恢复。

其他单元分类的关注点：

- `unit/protocol`：请求结构、响应兼容、缺失字段、未知枚举、URL 编码、超时和错误映射。
- `unit/live`：加入/离开、设备切换、重复事件、并发事件、资源释放和断线恢复。
- `unit/shell`：平台能力成功/取消/异常、路径与编码差异、持久化损坏和版本边界。

### UI widget 测试

适合验证：

- UI kit 布局和交互。
- v2 入口是否识别。
- 嵌入式 settings/home 的关键 affordance 是否存在。
- 输入框、composer、sidebar 这类容易回归的布局行为。

widget 测试优先验证用户可观察行为，不依赖私有 widget 层级或过细的像素实现。涉及菜单、焦点、选择、悬停和键盘操作时，要同时覆盖鼠标与键盘入口，以及组件销毁后的异步回调安全。

### 边界与回归测试

新增或修复功能时，至少检查与当前能力相关的边界：

- 文本：空值、空白、trim 前后、最短/最长/超长、简体中文、emoji、组合字符和大小写。
- 集合：零个、一个、多个、重复项、稳定排序、分页边界、最后一页和空结果。
- 时间：起止相同、跨月/年、闰日、时区、服务器时钟偏差、冷却倒计时和过期瞬间。
- 状态：首次加载、重复提交、并发请求、旧响应晚到、取消、重试、断线重连、退出后回调。
- 权限与身份：未登录、会话失效、普通成员、管理员、创建者、对象已删除或已离开房间。
- 数据兼容：缺失字段、旧缓存、未知类型、资源过期、记录存在但关联对象已删除。
- 组合筛选：关键词、日期、成员和分类单独使用及叠加使用，重置后应恢复默认全集。
- 批量操作：全选/全不选、部分选择、单条退化行为、选择项被实时删除、失败后的局部恢复。

修复缺陷时，回归测试应先复现缺陷的最小输入，再覆盖相邻边界；不要只断言“没有抛异常”，还要断言状态、可见结果和副作用。

### 服务端测试分类与数据库隔离

服务端位于相邻的 `gang-chat-server` 工程。Go 测试继续与被测 package 同目录，保证可以测试包内边界并符合 `go test ./...` 的发现规则；不要把所有 `*_test.go` 移到独立顶层测试目录。

同一 package 内按业务领域拆分测试文件。当前 chat API 测试使用 `api_auth_test.go`、`api_rooms_members_test.go`、`api_messages_test.go`、`api_notifications_test.go`、`api_search_test.go`、`api_stickers_uploads_test.go` 和 `api_live_test.go`；共享 HTTP harness 放 `api_harness_test.go`，数据库准备逻辑放 `mysql_test_support_test.go`，SQL fixture 放该 package 的 `testdata/`。过大的综合测试文件应按领域逐步拆分，但不得改变测试行为或为了拆分导出生产符号。

数据库集成测试必须遵守：

- 只连接名称以 `_test` 结尾或包含 `_test_` 的专用数据库，绝不连接开发、预发布或生产库。
- chat、idgen、musicbox 等会建表、清表或删表的 package 使用彼此独立的数据库和 DSN，不能共享 schema。当前分别使用 `GANG_TEST_MYSQL_DSN`、`GANG_TEST_IDGEN_MYSQL_DSN` 和 `GANG_TEST_MUSICBOX_MYSQL_DSN`。
- 测试开始前从受版本控制的 fixture 建立干净 schema，不能依赖上一次运行残留数据。
- 测试可重复运行，单独运行、整包运行和 `go test ./...` 的结果应一致。
- 对数据库时间、自动递增 ID 和行顺序不作隐式假设；需要顺序时在查询和断言中明确表达。
- 测试日志、fixture 和失败信息不得包含真实邮箱凭据、访问令牌或生产数据。

### 关联主页验证

`gang-chat-homepage` 是独立静态站点。无浏览器依赖的 JSON、版本号、资源链接和纯函数验证使用 Node 内置测试能力放在其 `tests/`，通过 `npm test` 运行；真实导航、下载和响应式布局再使用浏览器级测试。主页测试不放进客户端 `test/`，避免 Flutter 与网站工具链互相污染。

### 推荐命令

小改动先跑聚焦验证，例如：

```sh
flutter analyze lib/src/app/room_forms.dart test/unit/app/room_forms_test.dart
flutter test --no-pub test/unit/app/room_forms_test.dart
```

按分类运行客户端测试：

```sh
flutter test --no-pub test/unit/app
flutter test --no-pub test/unit/protocol
flutter test --no-pub test/unit/live
flutter test --no-pub test/unit/shell
flutter test --no-pub test/widget/ui
flutter test --no-pub test/widget/home
flutter test --no-pub test/widget/settings
flutter test --no-pub test/widget/shell
```

平台探针只在对应目标环境显式运行，例如：

```sh
flutter test integration_test/audio_enumeration_probe_test.dart -d windows
```

跨层或提交前跑全量：

```sh
flutter analyze
flutter test --no-pub
```

服务端按范围运行：

```sh
go test ./internal/chat -count=1
go test ./... -count=1
```

`-count=1` 用于避免 Go 测试缓存掩盖数据库隔离、时间或顺序问题。需要数据库的测试应在对应 DSN 已配置且指向独立测试库时运行；未配置时只能将其视为“集成测试未执行”，不能据此宣称服务端全量通过。

## 提交前检查清单

- `lib/src/app` 没有 Flutter/plugin/UI 依赖。
- UI 页面没有直接 import `file_selector`、`flutter_secure_storage`、`livekit_client` renderer。
- 新业务逻辑有 app 层测试。
- 新平台能力通过 shell/live adapter 注入。
- v1 原流程没有被 v2 改动破坏。
- 测试放在正确层级和模块目录，没有重新平铺到 `test/` 根目录。
- 缺陷修复包含最小复现和相关边界回归测试。
- `flutter analyze` 通过。
- 涉及多模块时 `flutter test --no-pub` 通过。
- 涉及服务端时，相关 package 测试与 `go test ./... -count=1` 通过，或明确记录未执行的数据库集成测试。

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
