# 音乐盒（Music Box）客户端对接文档

本文档面向客户端开发，说明如何对接服务端新增的「房间音乐盒」能力。

## 这是什么

音乐盒是**服务端侧**的房间播放器，和现有的 `music_*`（每个听众本地播放、再同步进度）是两套不同机制，不要混淆：

- 现有 `music_*`：每个客户端自己本地解码播放，客户端之间同步播放进度。
- **音乐盒 `music-box`**：服务端下载歌曲、转码成 Opus，通过一个机器人参与者把**单条音频轨**推进房间的 LiveKit 会话。听众什么都不用做，像听房间里某个人说话一样直接听到。

对客户端的核心影响：

1. **音频本身你不用管。** 只要用户已经加入了房间的 LiveKit 语音会话，音乐盒的声音会作为一个普通远端音频轨自动到达，和别人说话的轨道走的是同一条路。这个机器人参与者的 `identity` 固定是 `__musicbox__`，如果你要在 UI 上把它和真人区分开（比如不显示成「正在说话的成员」），就按这个 identity 过滤。
2. **你要做的是「控制台 + 状态展示」**：搜索、点歌、播放/暂停/切歌、看队列和当前播放状态。这些都走下面的 HTTP 接口，状态变化通过现有的 SSE 通道推送。

## 前置条件与降级

- 音乐盒**只有在服务端配置了 LiveKit 凭据时才启用**。没配的话，所有写接口返回 `503 music_box_unavailable`。
- 客户端判断是否展示音乐盒入口：调 `GET /music-box/state`，看返回里的 `enabled` 字段。`enabled: false` 时应隐藏或置灰相关 UI。
- 要听到声音，用户**必须已经在该房间的 LiveKit 会话里**（即已经 join live）。没进语音会话的人能看到队列和状态，但听不到音频——这点 UI 上要给用户预期。

## 通用约定

- Base path：`/api/v1`
- 鉴权：所有接口都要带 `Authorization: Bearer <access_token>`，和其他 chat 接口一致。
- `room_id` 是路径参数。
- 时间字段（`created_at`、`updated_at`）是字符串形式的毫秒时间戳（与现有接口口径一致）。
- 错误响应统一格式：

  ```json
  { "error": { "code": "validation_failed", "message": "track_id and title are required" } }
  ```

  对接时按 `error.code` 判断，`message` 仅用于调试/兜底展示。

## 接口列表

| 方法 | 路径 | 说明 | 权限 |
|------|------|------|------|
| GET | `/rooms/:room_id/music-box/state` | 拉取音乐盒完整状态快照 | 房间可访问者 |
| GET | `/rooms/:room_id/music-box/search` | 搜索歌曲 | 房间成员 |
| POST | `/rooms/:room_id/music-box/queue` | 点歌（加入队列） | 房间成员 |
| DELETE | `/rooms/:room_id/music-box/queue/:item_id` | 移除队列里的某首 | 点歌人本人或房管 |
| POST | `/rooms/:room_id/music-box/control` | 播放控制 | 房间成员 |

> 权限说明：搜索、点歌、播放控制目前对**任意房间成员**开放。移除队列项只允许**点这首歌的人本人**或**房管**操作，否则返回 `403 forbidden`。

---

### 1. 获取状态快照

```
GET /api/v1/rooms/:room_id/music-box/state
```

这是音乐盒的**唯一权威状态来源**。点歌、控制、删除等写操作的响应体也是同一个快照结构，SSE 推送的 payload 也是它。客户端应当用整个快照**覆盖**本地状态，不要做增量合并。

响应 `200`：

```json
{
  "enabled": true,
  "playback": {
    "state": "playing",
    "current_item_id": "itm_abc123",
    "position_ms": 42000,
    "volume": 100,
    "updated_at": "1749600000000"
  },
  "queue": [
    {
      "id": "itm_abc123",
      "source": "netease",
      "track_id": "108485",
      "title": "Always Online",
      "artist": "林俊杰",
      "pic_id": "109951163...",
      "duration_ms": 225000,
      "status": "ready",
      "file_size_bytes": 3873527,
      "error": "",
      "added_by_user_id": "usr_xxx",
      "created_at": "1749600000000"
    }
  ],
  "usage": { "used_bytes": 3873527, "limit_bytes": 209715200 }
}
```

字段说明：

- `playback.state`：枚举 `stopped` | `playing` | `paused`。
- `playback.current_item_id`：当前正在播放的队列项 `id`，对应 `queue[].id`。空字符串表示没有当前曲目。
- `playback.position_ms`：当前曲目已播放的毫秒数。注意这是服务端在状态变化时刻记录的值，**不会逐秒推送**。如果要做实时进度条，客户端应以 `playback.state == "playing"` 为准，从 `position_ms` 起本地起一个计时器自行推进，收到新快照时再校准。
- `playback.volume`：0–100，预留字段。
- `queue[].status`：队列项的音频处理生命周期，枚举见下。
- `queue[].error`：当 `status == "failed"` 时这里有失败原因，可展示给用户。
- `queue[].file_size_bytes`：转码后的 Opus 文件大小，`ready` 前为 0。
- `usage`：该房间音乐盒占用的磁盘字节 / 上限。点歌前可用它给用户提示「队列已接近上限」。

队列项状态机 `queue[].status`：

| 值 | 含义 | UI 建议 |
|----|------|---------|
| `pending` | 已入队，等待下载转码 | 显示「准备中」 |
| `downloading` | 正在下载/转码 | 显示「下载中」转圈 |
| `ready` | 转码完成，可播放 | 正常显示，可播放/可作为当前曲目 |
| `failed` | 下载或转码失败 | 显示错误态，附 `error` 文案，提供「移除」 |

---

### 2. 搜索歌曲

```
GET /api/v1/rooms/:room_id/music-box/search?keyword=林俊杰&source=netease&count=20&page=1
```

Query 参数：

- `keyword`（必填）：搜索关键词。也兼容 `name` 作为别名。为空返回 `400 validation_failed`。
- `source`（选填）：音源，如 `netease`、`tencent` 等。不传走服务端默认音源。
- `count`（选填）：每页条数。
- `page`（选填）：页码。

响应 `200`：

```json
{
  "results": [
    {
      "track_id": "108485",
      "name": "Always Online",
      "artists": ["林俊杰"],
      "pic_id": "109951163...",
      "source": "netease"
    }
  ]
}
```

> 注意 `artists` 是**字符串数组**（可能多个艺人），展示时自行用 `、` 之类拼接。点歌时需要把这些字段映射成点歌请求体里的对应字段（`name → title`，`artists` 拼成 `artist` 字符串）。

错误：上游音乐 API 异常时返回 `502 upstream_error`。上游偶发抽风（空结果/超时），建议客户端对「搜索无结果」和「搜索失败」做不同提示，必要时允许用户重试。

---

### 3. 点歌（加入队列）

```
POST /api/v1/rooms/:room_id/music-box/queue
Content-Type: application/json
```

请求体：

```json
{
  "source": "netease",
  "track_id": "108485",
  "title": "Always Online",
  "artist": "林俊杰",
  "pic_id": "109951163...",
  "duration_ms": 225000
}
```

- `track_id`、`title` 必填，缺失返回 `400 validation_failed`。
- 其余字段选填，建议尽量从搜索结果原样带上（`pic_id` 用于封面，`duration_ms` 用于进度条）。
- `duration_ms` 可不传；服务端转码完成后会用 ffprobe 探测真实时长并回填到状态快照里。

响应 `201`：返回与 `GET /state` 相同的**完整状态快照**（此时新歌通常是 `pending` 状态）。

错误：

- `409 queue_full`：该房间音乐盒磁盘占用已达上限，提示用户稍后再点或先清理队列。
- `503 music_box_unavailable`：音乐盒未启用。

> 点歌后不要本地乐观插入就完事——以响应快照（以及随后的 SSE 推送）为准刷新队列，因为 `status` 会从 `pending → downloading → ready` 变化。

---

### 4. 移除队列项

```
DELETE /api/v1/rooms/:room_id/music-box/queue/:item_id
```

`item_id` 是 `queue[].id`。

响应 `200`：返回完整状态快照。

错误：

- `403 forbidden`：当前用户既不是这首歌的点歌人、也不是房管。客户端可据此只对「自己点的」或「房管」展示删除按钮。

---

### 5. 播放控制

```
POST /api/v1/rooms/:room_id/music-box/control
Content-Type: application/json
```

请求体：

```json
{ "action": "pause" }
```

`action` 枚举（其它值返回 `400 validation_failed`）：

| action | 含义 |
|--------|------|
| `play` | 开始播放（从队列里第一首可播放的开始） |
| `pause` | 暂停 |
| `resume` | 从暂停处继续 |
| `skip` / `next` | 跳到下一首（两者等价） |
| `stop` | 停止播放 |

响应 `200`：返回完整状态快照。

---

## 实时状态推送（SSE）

音乐盒**不需要单独的推送通道**，复用现有的 `GET /api/v1/me/stream` SSE 连接。

当某个房间的队列或播放状态发生变化（点歌、转码完成、播放/暂停/切歌、删除等），服务端会向该房间的订阅者推送一条事件：

- `event` 名：`music_box_changed`
- `data` 是标准事件信封：

  ```
  event: music_box_changed
  data: {"type":"music_box_changed","room_id":"room_xxx","data":{ ...与 GET /state 完全相同的快照... }}
  ```

客户端处理建议：

1. 在 SSE 的事件分发里新增 `music_box_changed` 分支。
2. 取 `data.data`（即状态快照），按 `data.room_id` 找到对应房间，整体覆盖本地音乐盒状态。
3. 不要做字段级 diff，直接覆盖即可（服务端就是按「全量快照覆盖」的约定设计的）。

> 进度条注意点（重申）：SSE **不会**逐秒推 `position_ms`。`state == "playing"` 时，客户端基于最近一次快照的 `position_ms` + 本地计时推进；每次收到新快照就重新对齐。`pause`/`stop` 时停掉本地计时器。

## 封面图

目前服务端**没有**暴露「`pic_id` → 封面 URL」的转换接口。搜索结果和队列项里都带了 `pic_id`，但要拿到真实图片地址还需要服务端补一个解析接口（gdmusic 内部有 `AlbumArt` 能力，只是还没接成路由）。

如果客户端需要展示封面，请先和服务端确认是否要新增这个接口（建议形如 `GET /music-box/cover?pic_id=...&size=300|500`），不要在客户端直接拼第三方音乐 API 的地址。在该接口就绪前，封面位可先用占位图。

## 对接 checklist

- [ ] 进房后调一次 `GET /music-box/state`，根据 `enabled` 决定是否展示音乐盒入口。
- [ ] 搜索 → 点歌：把搜索结果字段正确映射到点歌请求体（`name→title`、`artists→artist`）。
- [ ] 队列 UI 按 `status` 渲染（准备中/下载中/可播放/失败）。
- [ ] 接入 SSE `music_box_changed`，整体覆盖本地状态。
- [ ] 进度条用 `position_ms + 本地计时` 推进，收到快照时校准。
- [ ] 删除按钮按「本人/房管」展示，并兜底处理 `403`。
- [ ] 音频本身依赖已加入 LiveKit 语音会话；未入会时给用户「加入语音才能听」的提示。
- [ ] 处理 `503 music_box_unavailable`、`409 queue_full`、`502 upstream_error` 几种态。
- [ ] 在房间成员列表里按 identity `__musicbox__` 过滤掉机器人参与者（如不想把它当成真人显示）。

## 待服务端确认 / 尚未就绪的点

> 这几项请对接前与服务端同步，避免按本文档实现后发现行为不一致：

1. **封面接口尚未提供**（见上）。
2. **LiveKit 播放链路**：下载 + 转 Opus 已实测通过，但「机器人入房 + 推流 + 客户端真实听到声音」这一环依赖运行中的 LiveKit 服务，服务端尚未做真机联调。首次联调时建议客户端和服务端一起验证音频是否真正可听、暂停/切歌是否即时生效。
3. **音乐盒的上线时机**：当前实现是「队列里有歌且触发播放时机器人才入房，队列空闲一段时间后自动退房」。产品侧倾向改为「房间内只要有人，音乐盒就常驻在线」。这块行为可能调整，若涉及客户端展示（比如音乐盒在线状态指示），以最终服务端实现为准。
