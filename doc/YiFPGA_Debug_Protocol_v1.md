# YiFPGA Studio Debug Protocol v1

## 1. 设计目标

YiFPGA Studio Debug Protocol v1 是 Debug Core、UART/JTAG Transport 和 Viewer 的共同协议。

设计原则：

- 二进制帧，减少 UART 带宽浪费。
- 单向优先，第一版只定义 FPGA 到 PC。
- Transport 无关，UART、USB、Ethernet、PCIe 后续都可以承载同一帧格式。
- RTL 简单，第一版使用 XOR checksum。
- 可升级，保留版本字段和消息类型空间。

## 2. 字节序

所有多字节整数均使用 little-endian：

- `u16`：低字节在前。
- `u32`：最低有效字节在前。

## 3. 帧格式

```text
+--------+--------+--------+--------+-------------+----------+
| SOF    | VER    | TYPE   | LEN    | PAYLOAD     | CHECKSUM |
| 1 byte | 1 byte | 1 byte | 1 byte | 0..32 bytes | 1 byte   |
+--------+--------+--------+--------+-------------+----------+
```

字段：

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `SOF` | `0xA5` | 帧起始字节 |
| `VER` | `0x01` | 协议版本 |
| `TYPE` | 见消息类型表 | 消息类型 |
| `LEN` | `0..32` | payload 字节数 |
| `PAYLOAD` | 变长 | 消息内容 |
| `CHECKSUM` | XOR | 校验字节 |

Checksum 计算范围：

```text
CHECKSUM = VER xor TYPE xor LEN xor PAYLOAD[0] xor ... xor PAYLOAD[LEN-1]
```

`SOF` 不参与 checksum。

## 4. 消息类型

| Type | 名称 | 说明 |
| --- | --- | --- |
| `0x01` | `HEARTBEAT` | 心跳 |
| `0x02` | `DEBUG_PRINT` | 调试打印 |
| `0x03` | `EVENT` | 离散事件 |
| `0x04` | `WATCH` | 变量或寄存器观察值 |
| `0x05` | `STATUS` | Debug Core 状态 |
| `0x10` | `TRACE_SPAN_BEGIN` | Trace 区间开始 |
| `0x11` | `TRACE_SPAN_END` | Trace 区间结束 |
| `0x12` | `TRACE_MARK` | Trace 瞬时事件标记 |
| `0x13` | `TRACE_VALUE` | Trace 低频数值采样 |
| `0x14` | `TRACE_DROP` | Trace 丢弃或限流提示 |
| `0x20` | `MONITOR_READ_REQ` | PC 请求读取 Monitor register |
| `0x21` | `MONITOR_READ_RESP` | FPGA 返回 Monitor register 读响应 |
| `0x22` | `MONITOR_WRITE_REQ` | PC 请求写入 Monitor register |
| `0x23` | `MONITOR_WRITE_RESP` | FPGA 返回 Monitor register 写响应 |
| `0x24` | `MONITOR_BURST_READ_REQ` | PC 请求连续读取，预留 |
| `0x25` | `MONITOR_BURST_READ_RESP` | FPGA 返回连续读取响应，预留 |
| `0x26` | `MONITOR_POLL_CFG` | PC 配置 FPGA 侧轮询，预留 |
| `0x27` | `MONITOR_EVENT` | FPGA 上报 Monitor 状态变化或拒绝事件 |
| `0x28` | `MONITOR_DISCOVER_REQ` | PC 查询寄存器 map 摘要，预留 |
| `0x29` | `MONITOR_DISCOVER_RESP` | FPGA 返回寄存器 map 摘要，预留 |
| `0x30` | `PROFILER_SNAPSHOT` | FPGA 上报周期性能指标快照 |
| `0x31` | `PROFILER_ALERT` | FPGA 上报性能阈值、溢出、下溢或 timeout |
| `0x32` | `PROFILER_COUNTER` | 单计数器低频更新，预留 |
| `0x33` | `PROFILER_LATENCY` | 专用延迟统计帧，预留 |
| `0x34` | `PROFILER_DISCOVER` | 指标 manifest 摘要，预留 |
| `0x35` | `PROFILER_CFG_REQ` | Profiler 专用配置请求，预留，P0 由 Monitor 替代 |
| `0x36` | `PROFILER_CFG_RESP` | Profiler 专用配置响应，预留 |
| `0x40` | `LA_CAPTURE_HEADER` | Logic Analyzer 捕获元信息 |
| `0x41` | `LA_SAMPLE_DATA` | Logic Analyzer 分片 sample 数据 |
| `0x42` | `LA_CAPTURE_STATUS` | Logic Analyzer 捕获状态、错误和进度 |
| `0x43` | `LA_TRIGGER_EVENT` | Logic Analyzer 触发命中事件 |
| `0x44` | `LA_CHANNEL_MANIFEST` | Logic Analyzer 通道定义摘要，P0 可选 |
| `0x45` | `LA_CFG_REQ` | Logic Analyzer 专用配置请求，预留，P0 由 Monitor 替代 |
| `0x46` | `LA_CFG_RESP` | Logic Analyzer 专用配置响应，预留 |

保留范围：

| Type 范围 | 用途 |
| --- | --- |
| `0x15..0x1F` | Trace 保留 |
| `0x20..0x2F` | Monitor |
| `0x30..0x3F` | Profiler |
| `0x40..0x4F` | Logic Analyzer |
| `0xF0..0xFF` | 实验和厂商扩展 |

## 5. Payload 布局

### 5.1 HEARTBEAT

```text
u32 timestamp
```

长度：4 字节。

### 5.2 DEBUG_PRINT

```text
u32 timestamp
u16 print_id
u32 arg0
u32 arg1
```

长度：14 字节。

说明：

- FPGA 第一版不做字符串格式化。
- `print_id` 由 Viewer 映射成文本模板。
- `arg0` 和 `arg1` 是模板参数或原始调试值。

### 5.3 EVENT

```text
u32 timestamp
u16 event_id
u8  level
u32 arg0
```

长度：11 字节。

`level` 建议值：

| Level | 名称 |
| --- | --- |
| `0` | Debug |
| `1` | Info |
| `2` | Warning |
| `3` | Error |

### 5.4 WATCH

```text
u32 timestamp
u16 watch_id
u32 value
```

长度：10 字节。

同一个 `watch_id` 在 Viewer 中更新最新值，同时可追加到日志。

### 5.5 STATUS

```text
u32 timestamp
u16 buffer_used
u16 drop_count
u16 packet_count
```

长度：10 字节。

说明：

- `buffer_used` 表示 Debug Core 内部缓冲占用。
- `drop_count` 表示因缓冲满或发送拥塞丢弃的包数量。
- `packet_count` 表示成功进入发送队列的包数量。

### 5.6 TRACE_SPAN_BEGIN

```text
u32 timestamp
u16 trace_id
u16 instance_id
u32 arg0
```

长度：12 字节。

说明：

- `trace_id` 表示模块或事务类型，例如 DMA、Frame、FIFO、Interrupt。
- `instance_id` 表示同类事务实例，用于匹配 begin/end。
- `arg0` 可存放 frame_id、dma_desc_id、fifo_level 或业务状态。

### 5.7 TRACE_SPAN_END

```text
u32 timestamp
u16 trace_id
u16 instance_id
u8  status
u32 arg0
```

长度：13 字节。

`status` 建议值：

| Status | 名称 | 说明 |
| --- | --- | --- |
| `0` | `OK` | 正常结束 |
| `1` | `WARN` | 结束但存在告警 |
| `2` | `ERROR` | 异常结束 |
| `3` | `TIMEOUT` | 超时 |

### 5.8 TRACE_MARK

```text
u32 timestamp
u16 trace_id
u8  level
u32 arg0
```

长度：11 字节。

用于记录 IRQ 触发、FIFO almost_full、DMA descriptor done、frame sync 等瞬时事件。`level` 复用 EVENT 的 Debug/Info/Warning/Error 建议值。

### 5.9 TRACE_VALUE

```text
u32 timestamp
u16 trace_id
u16 value_id
u32 value
```

长度：12 字节。

用于记录 FIFO level、pending descriptor 数量、frame counter 等低频采样值。同一组 `trace_id/value_id` 在 Viewer 中应保留最新值，也可进入历史序列。

### 5.10 TRACE_DROP

```text
u32 timestamp
u16 trace_id
u32 drop_count
```

长度：10 字节。

用于提示 Trace Adapter 或 Debug Core 因限流、缓冲不足等原因丢弃了 Trace 事件。`trace_id = 0` 表示全局 Trace 丢弃统计。

### 5.11 Monitor 公共约定

第三阶段 Monitor 开始使用同一帧格式承载双向命令和响应。PC 到 FPGA 的 request 帧与 FPGA 到 PC 的 response 帧都使用 `SOF + VER + TYPE + LEN + PAYLOAD + CHECKSUM`，多字节字段仍为 little-endian。

Monitor request/response 必须包含 `seq` 字段。Viewer 每发送一个 request 分配一个 16 bit `seq`，FPGA 在 response 中原样返回，用于匹配 pending 命令、检测超时和识别迟到响应。

Monitor status 建议值：

| Status | 名称 | 说明 |
| --- | --- | --- |
| `0` | `OK` | 成功 |
| `1` | `BAD_ADDR` | 地址不存在 |
| `2` | `DENIED` | 权限不允许 |
| `3` | `BUSY` | Monitor core 忙或目标暂不可访问 |
| `4` | `BAD_LEN` | 长度、宽度或对齐错误 |
| `5` | `BAD_VALUE` | 写入值非法 |
| `6` | `TIMEOUT` | 内部访问超时 |

`addr` 是 Monitor register map 的 16 bit 逻辑地址，不是 FPGA 物理地址。第一版宽度 `width` 支持 `1/2/4` 字节，P0 实现可以先固定为 `4`。

### 5.12 MONITOR_READ_REQ

```text
u16 seq
u16 addr
u8  width
```

长度：5 字节。

### 5.13 MONITOR_READ_RESP

```text
u32 timestamp
u16 seq
u16 addr
u8  status
u8  width
u32 value
```

长度：14 字节。即使 `width < 4`，`value` 也使用 32 bit 承载，未使用高位由 RTL 置 0。

### 5.14 MONITOR_WRITE_REQ

```text
u16 seq
u16 addr
u8  width
u32 value
u32 mask
```

长度：13 字节。`mask` 支持位级修改：

```text
new_value = (old_value & ~mask) | (value & mask)
```

触发型寄存器可以要求 `mask = 0xFFFFFFFF`。

### 5.15 MONITOR_WRITE_RESP

```text
u32 timestamp
u16 seq
u16 addr
u8  status
u32 old_value
u32 new_value
```

长度：17 字节。若 `status != OK`，`old_value/new_value` 可以返回 0 或当前实际值；Viewer 必须以 `status` 为准，不应在失败响应中更新寄存器值。

### 5.16 Profiler 公共约定

第四阶段 Profiler 使用同一帧格式承载 FPGA 到 PC 的窗口化性能统计。P0 中 Profiler 配置、清零、启停和阈值设置复用 Monitor register map，避免增加第二套控制通道。

Profiler `metric_id` 是 16 bit 逻辑指标编号，不是硬件地址。P0 静态指标建议：

| metric_id | 名称 | 类型 | 单位 |
| --- | --- | --- | --- |
| `0x0001` | `AXIS_DEMO_THROUGHPUT` | Throughput | bytes/window |
| `0x0101` | `FIFO_DEMO_LEVEL` | FIFO | level |
| `0x0201` | `DEMO_LATENCY` | Latency | cycles |
| `0x0301` | `FRAME_RATE` | Frame Rate | frames/window |

`PROFILER_SNAPSHOT` 的 `value0..value3` 含义由 `metric_id` 类型决定：

| 类型 | value0 | value1 | value2 | value3 |
| --- | --- | --- | --- | --- |
| Throughput | bytes/words | beats | active_cycles | stall_cycles |
| FIFO | current_level | max_level | min_level | overflow/underflow |
| Latency | count | min | max | avg |
| Frame Rate | frame_count | dropped_frames | min_interval | max_interval |

Profiler flags：

| Bit | 名称 | 说明 |
| --- | --- | --- |
| `0` | `VALID` | 当前 snapshot 有效 |
| `1` | `SATURATED` | 计数器发生饱和 |
| `2` | `WINDOW_RESET` | 本帧之后窗口已清零 |
| `3` | `PARTIAL` | 窗口未满但被提前上报 |
| `4` | `ALERT` | 同窗口存在异常 |

Profiler alert code：

| Code | 名称 | 说明 |
| --- | --- | --- |
| `1` | `THRESHOLD_HIGH` | 指标超过上限 |
| `2` | `THRESHOLD_LOW` | 指标低于下限 |
| `3` | `OVERFLOW` | 统计计数器溢出或饱和 |
| `4` | `UNDERFLOW` | FIFO 或流控下溢 |
| `5` | `TIMEOUT` | 延迟超过窗口上限 |
| `6` | `DROP` | Profiler 或 Debug Core 丢弃统计帧 |

### 5.17 PROFILER_SNAPSHOT

```text
u32 timestamp
u16 metric_id
u16 flags
u32 sample_cycles
u32 value0
u32 value1
u32 value2
u32 value3
u16 overflow_count
u16 reserved
```

长度：32 字节，正好等于 v1 帧的最大 payload 长度。`sample_cycles` 表示当前统计窗口对应的 Debug Core clock cycle 数。`overflow_count` 表示本窗口内统计饱和、丢弃或溢出次数。

### 5.18 PROFILER_ALERT

```text
u32 timestamp
u16 metric_id
u8  level
u8  code
u32 arg0
u32 arg1
```

长度：16 字节。`level` 复用 EVENT 的 Debug/Info/Warning/Error 建议值；`code` 使用 Profiler alert code。

### 5.19 Logic Analyzer 公共约定

第五阶段 Logic Analyzer 使用同一帧格式承载 FPGA 到 PC 的捕获后分片波形数据。P0 中 LA 配置、arm、stop、clear、force trigger 和 start readout 复用 Monitor register map，避免增加第二套控制通道。

P0 约束：

- `sample_width_bits <= 32`。
- `sample_bytes` 只接受 1、2、4。
- 单帧 payload 仍遵守 `LEN <= 32`。
- 同一 `capture_id` 的 chunk 推荐顺序发送，但 Viewer 必须检查 `chunk_index` 和 `first_sample_index`。
- 缺片、乱序、错误长度和非法 sample packing 必须进入 parser counters，不应中断后续帧解析。

Logic Analyzer flags：

| Bit | 名称 | 说明 |
| --- | --- | --- |
| `0` | `VALID` | 本次捕获有效 |
| `1` | `TRIGGERED` | 已命中 trigger |
| `2` | `FORCED` | 由 stop/force 结束 |
| `3` | `OVERFLOW` | capture 或 readout 发生溢出 |
| `4` | `PARTIAL` | 未采满即结束 |

Logic Analyzer state 建议：

| 值 | 名称 | 说明 |
| --- | --- | --- |
| `0` | `IDLE` | 未使能 |
| `1` | `ARMED` | 等待 trigger |
| `2` | `CAPTURING` | 已触发或正在填充窗口 |
| `3` | `DONE` | 捕获完成，可读出 |
| `4` | `READOUT` | 正在上传分片 |
| `5` | `ERROR` | 配置或运行错误 |

### 5.20 LA_CAPTURE_HEADER

```text
u32 capture_id
u32 timestamp
u16 sample_width_bits
u16 sample_count
u16 trigger_index
u16 flags
u32 sample_period_cycles
u16 channel_count
u16 reserved
```

长度：24 字节。`sample_period_cycles` 表示相邻 sample 之间的 Debug Core clock cycle 数。`trigger_index` 是本次 capture 内触发 sample 的索引。

### 5.21 LA_SAMPLE_DATA

```text
u32 capture_id
u16 chunk_index
u16 first_sample_index
u8  sample_bytes
u8  sample_count
u16 flags
u8  data[20]
```

长度：32 字节。`data` 按 little-endian 紧凑排列，不足 20 字节的尾帧补 0。`sample_count * sample_bytes` 不能超过 20。

### 5.22 LA_CAPTURE_STATUS

```text
u32 timestamp
u32 capture_id
u8  state
u8  error
u16 samples_written
u16 chunks_sent
u16 chunks_total
u32 status_flags
```

长度：20 字节。`chunks_sent/chunks_total` 用于 Viewer 显示 readout 进度。

### 5.23 LA_TRIGGER_EVENT

```text
u32 timestamp
u32 capture_id
u16 trigger_index
u16 trigger_channel
u32 sample_value
u32 trigger_value
```

长度：20 字节。P0 若 trigger 是多条件组合，`trigger_channel` 可填第一个命中条件的通道号。

## 6. Parser 行为

Viewer parser 必须支持：

- 在任意字节流中搜索 `SOF`。
- 收到不完整帧时等待后续字节。
- `LEN > 32` 时丢弃该帧并重新同步。
- checksum 错误时计数并重新搜索下一个 `SOF`。
- 未知 `VER` 或未知 `TYPE` 时保留原始帧并计数。
- `TRACE_SPAN_BEGIN` 按 `trace_id + instance_id` 记录 open span。
- `TRACE_SPAN_END` 匹配 open span 并生成完整 span；无法匹配时保留为 orphan span。
- `TRACE_MARK`、`TRACE_VALUE`、`TRACE_DROP` 分别进入独立 Trace 集合，供时间轴、统计和 JSONL 导出使用。
- `MONITOR_READ_RESP` 和 `MONITOR_WRITE_RESP` 按 `seq` 匹配 pending request；匹配失败时记录为未知响应。
- Monitor response `status != OK` 时记录错误，不更新寄存器当前值。
- pending Monitor request 超时后必须清除 pending 状态，并记录 `TIMEOUT` 错误。
- `PROFILER_SNAPSHOT` 长度必须为 32 字节，解析后按 `metric_id` 更新 latest 和 history。
- `PROFILER_ALERT` 长度必须为 16 字节，解析后进入 alert 集合。
- 未知 `metric_id` 的 Profiler 帧不得丢弃，应以 `metric_0xNNNN` 形式保留。
- Profiler snapshot 的 `SATURATED` flag 或 `overflow_count > 0` 必须计入 overflow/notice 统计。
- Profiler payload 长度错误必须计入 malformed，但不应中断后续帧解析。
- `LA_CAPTURE_HEADER` 长度必须为 24 字节，解析后创建或更新 capture model。
- `LA_SAMPLE_DATA` 长度必须为 32 字节，且 `sample_bytes` 只能为 1、2、4，`sample_count * sample_bytes <= 20`。
- `LA_CAPTURE_STATUS` 长度必须为 20 字节，解析后更新 capture 状态和 readout 进度。
- `LA_TRIGGER_EVENT` 长度必须为 20 字节，解析后更新 capture trigger marker。
- LA data 先于 header 到达时，Viewer 应创建占位 capture 并标记 `missing_header`。
- LA chunk 必须校验 `capture_id`、`chunk_index` 和 `first_sample_index`，缺片、乱序、重复或重叠 sample 必须可见。
- LA payload 长度错误、非法 sample packing 和保留 LA type 必须计入 malformed，但不应中断后续帧解析。

## 7. 示例帧

Heartbeat 示例：

```text
A5 01 01 04 78 56 34 12 1D
```

含义：

- `SOF = A5`
- `VER = 01`
- `TYPE = 01`
- `LEN = 04`
- `timestamp = 0x12345678`
- `CHECKSUM = 1D`

Trace span begin 示例：

```text
A5 01 10 0C 64 00 00 00 01 00 42 00 10 00 00 00 2A
```

含义：

- `TYPE = 10` (`TRACE_SPAN_BEGIN`)
- `LEN = 0C`
- `timestamp = 100`
- `trace_id = 0x0001`
- `instance_id = 0x0042`
- `arg0 = 0x00000010`

Monitor read request 示例：

```text
A5 01 20 05 01 00 0C 00 04 2D
```

含义：

- `TYPE = 20` (`MONITOR_READ_REQ`)
- `LEN = 05`
- `seq = 1`
- `addr = 0x000C`
- `width = 4`

Monitor write request 示例：

```text
A5 01 22 0D 02 00 0C 00 04 05 00 00 00 0F 00 00 00 2E
```

含义：

- `TYPE = 22` (`MONITOR_WRITE_REQ`)
- `LEN = 0D`
- `seq = 2`
- `addr = 0x000C`
- `width = 4`
- `value = 0x00000005`
- `mask = 0x0000000F`

Profiler snapshot 示例：

```text
A5 01 30 20 90 01 00 00 01 00 01 00 A0 86 01 00 00 20 00 00 00 04 00 00 B0 04 00 00 0C 00 00 00 00 00 00 00 3B
```

含义：

- `TYPE = 30` (`PROFILER_SNAPSHOT`)
- `LEN = 20`
- `timestamp = 400`
- `metric_id = 0x0001` (`AXIS_DEMO_THROUGHPUT`)
- `flags = 0x0001` (`VALID`)
- `sample_cycles = 100000`
- `value0 = 8192`
- `value1 = 1024`
- `value2 = 1200`
- `value3 = 12`
- `overflow_count = 0`

Profiler alert 示例：

```text
A5 01 31 10 AE 01 00 00 01 01 02 03 3C 00 00 00 01 00 00 00 B3
```

含义：

- `TYPE = 31` (`PROFILER_ALERT`)
- `LEN = 10`
- `timestamp = 430`
- `metric_id = 0x0101` (`FIFO_DEMO_LEVEL`)
- `level = 2` (`Warning`)
- `code = 3` (`OVERFLOW`)
- `arg0 = 60`
- `arg1 = 1`
