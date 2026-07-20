# YiFPGA Studio Web Viewer 使用说明

## 1. 浏览器要求

Web Viewer 位于：

```text
tools/viewer/web/index.html
```

请使用 Chrome 或 Edge。Web Serial API 通常要求安全上下文；本地 `file://` 页面在当前测试环境可用，如浏览器策略阻止串口访问，可用本地 HTTP 服务打开。

## 2. 连接板卡

1. 下载 bitstream。
2. 将 FPGA `uart_tx` 接到 PC 串口 RX，确保共地。
3. 打开 `tools/viewer/web/index.html`。
4. 选择 baud rate，板级 demo 默认 `115200`。
5. 点击 `Connect`，选择对应串口。

连接成功后应能看到：

- `HEARTBEAT` 每秒追加一次。
- `STATUS` 约 50 Hz 更新。
- `WATCH` 约 100 Hz 更新，并在 Watch 视图按 ID 合并。
- `EVENT` 约 10 Hz 更新。
- `DEBUG_PRINT` 约 5 Hz 更新。

## 3. 视图说明

### Log

按接收顺序显示最近日志。当前最多保留 300 行，避免长时间运行时页面无限增长。

### Watch

按 `watch_id` 合并显示最新值，同时显示 timestamp 和更新次数。

### Events

按 `event_id` 统计计数，显示最近 level 和 arg0。

### Status

显示：

- `buffer_used`
- `drop_count`
- `packet_count`
- `lastTimestamp`

`drop_count > 0` 时会高亮。

### Trace

Trace 视图用于显示 `TRACE_SPAN_BEGIN`、`TRACE_SPAN_END`、`TRACE_MARK`、`TRACE_VALUE` 和 `TRACE_DROP`。

- 时间轴按 `trace_id` 分泳道显示，内置常用映射：DMA、Frame、FIFO、Interrupt。
- Span 以横条显示，点击后在右侧详情中查看开始时间、结束时间、持续时间、status、arg0 和 orphan 状态。
- Mark 以竖向标记显示，warning/error 级别会高亮；drop 会作为异常标记显示。
- Latest Values 表格按 `trace_id/value_id` 显示最新采样值，适合观察 FIFO level 等低频计数。
- 顶部过滤器支持按泳道、status/problem 和 timestamp 范围筛选。
- 统计区显示当前过滤结果中的 span 数、平均持续时间、最大持续时间和异常数量。

`Inject Sample` 会注入一组无硬件 Trace 场景：Frame span、DMA span、FIFO almost_full mark、FIFO level value、IRQ mark、DMA timeout span 和 Trace drop。用于验收 Trace 时间轴、异常高亮、详情面板和 JSONL 导出。

### Monitor

Monitor 视图用于在线读写 FPGA 侧显式导出的安全寄存器。当前静态 map 包括：

- `MONITOR_ID`
- `MONITOR_VERSION`
- `CONTROL`
- `LED_CONTROL`
- `DEMO_PERIOD`
- `COUNTER0`
- `CLEAR_COUNTERS`
- `ERROR_STATUS`
- `PROFILER_CONTROL`
- `PROFILER_VERSION`
- `PROFILER_STATUS`
- `PROFILER_SAMPLE_PERIOD`
- `PROFILER_CLEAR`
- `PROFILER_METRIC_MASK`

每行 `Read` 会发送 `MONITOR_READ_REQ`。`RW/W1C` 行提供 value 和 mask 输入，点击 `Write` 并确认后发送 `MONITOR_WRITE_REQ`。`TRIGGER` 行提供 `Trigger` 按钮，当前用于 `CLEAR_COUNTERS`。启用 `Poll` 后 Viewer 会按 Interval 周期读取全部寄存器；pending 未完成时会跳过下一轮，避免串口断开后堆积请求。

`Inject Sample` 也会注入 Monitor read/write response，用于无硬件验收 Monitor 表格、错误面板和 JSONL 导出。

### Profiler

Profiler 视图用于展示 `PROFILER_SNAPSHOT` 和 `PROFILER_ALERT`：

- 指标卡显示 Throughput、FIFO、Latency、Frame Rate 的最新窗口值、flags 和历史长度。
- 趋势图按当前选中的 metric 绘制最近 snapshot，`Value` 下拉可切换 `value0..value3` 对应字段。
- 指标表显示 metric 名称、类型、主值、sample window、min/max/avg、flags 和更新时间。
- Alert 面板显示 threshold、overflow、underflow、timeout、drop 等事件，并支持按 Warning/Error 过滤。
- 控制区复用 Monitor 请求生成 Profiler enable、disable、sample period、clear 和 status read 操作。未连接串口时这些操作会在 Monitor errors 中记录为 disconnected。

`Inject Sample` 会额外注入四类 `PROFILER_SNAPSHOT` 和一条 `PROFILER_ALERT`，用于无硬件验收 Profiler 视图、JSONL 导出和 `window.yifpgaViewerTest.injectProfilerSample()` 测试钩子。

### Logic Analyzer

M24 adds a Logic Analyzer panel above Trace. It renders parsed `LA_CAPTURE_HEADER`,
`LA_SAMPLE_DATA`, `LA_CAPTURE_STATUS`, and `LA_TRIGGER_EVENT` records as digital
waveforms.

- `Inject Sample` now injects one LA capture, a trigger event, sample chunks, a done
  status, and one malformed chunk for UI/error-path validation.
- `Arm`, `Stop`, `Force`, `Clear`, and `Readout` write `LA_COMMAND` through the
  Monitor request path.
- `Apply` writes `LA_SAMPLE_DIVISOR`, `LA_CAPTURE_DEPTH`, `LA_PRETRIGGER_DEPTH`,
  trigger mode/channel/value/mask, and `LA_CHANNEL_MASK`.
- The waveform supports sample-based pan/zoom, cursor A/B, trigger marker, channel
  visibility, and compact bus-value lanes.
- `Export JSONL` includes LA header/sample/status/trigger records and
  `la_parser_counters`.
- `Export VCD` exports the latest visible-channel capture as a GTKWave-compatible VCD.

Browser test hook:

```javascript
const api = window.yifpgaViewerTest;
api.clearAll();
api.injectLogicAnalyzerSample();
```
## 4. 操作

- `Connect`：请求串口授权并开始读取。
- `Disconnect`：停止读取并关闭串口。
- `Inject Sample`：注入测试帧，不需要硬件即可验证 UI。
- `Pause/Resume`：暂停界面刷新，但仍继续接收和解析数据。
- `Clear`：清空接收缓存、日志、统计和视图。
- `Export CSV`：若当前 Profiler metric 有历史记录，则导出该 metric 的 snapshot 历史；否则导出 Log 表。
- `Export JSONL`：导出 Log/Event/Watch/Status、Trace、Monitor、Profiler 数据和 parser counters 快照。Trace 记录使用 `trace_span`、`trace_open_span`、`trace_mark`、`trace_value`、`trace_drop`；Monitor 记录使用 `monitor_read`、`monitor_write`、`monitor_timeout`、`monitor_error`；Profiler 记录使用 `profiler_snapshot`、`profiler_alert` 和 `profiler_counters`。

## 5. 常见问题

### 看不到串口

- 确认浏览器为 Chrome 或 Edge。
- 确认串口没有被 Vivado Serial Terminal、PuTTY、PowerShell 验证脚本等其他程序占用。
- Windows 设备管理器中确认 COM 口存在。

### 有帧但 checksum 错误增长

- 检查 baud rate 是否与 RTL 一致。
- 检查 UART 电平和接线方向。
- 检查地线是否共地。

### drop count 增长

- 降低 watch/status/event 上报频率。
- 提高 `UART_BAUD`。
- 增大 ring buffer 深度。

### 页面长时间运行变慢

当前第一阶段 Web Viewer 已限制 Log 行数，但仍未做虚拟列表。长时间大吞吐场景可优先使用 JSONL 导出或命令行验证脚本。
## M10 Web Viewer Performance Check

M10 Trace enables continuous span/mark/value traffic. The Trace timeline now batches UI rendering with `requestAnimationFrame` and renders only the latest visible window by default, so live serial input does not rebuild thousands of DOM nodes for every incoming frame.

运行本地 Chromium 系浏览器 headless 压测（自动发现 Edge、Chrome 或 Chromium）：

```powershell
python tools\viewer\web\run_perf_test.py
```

也可显式指定浏览器：

```bash
python tools/viewer/web/run_perf_test.py --browser /path/to/chromium
# 或设置 YIFPGA_VIEWER_BROWSER=/path/to/chromium
```

脚本访问本机 CDP 时会显式绕过 `HTTP_PROXY`/`HTTPS_PROXY`，避免缺少 `NO_PROXY`
导致 `127.0.0.1` 请求被代理并超时。

Expected output is similar to:

```text
{"frames":11185,"checksumErrors":0,"syncDrops":0,"unknownFrames":0,"spans":2400,"marks":2400,"values":800,"profilerSnapshots":4,"profilerAlerts":1,"profilerOverflowSnapshots":1,"traceNodes":1200,"elapsedMs":435,"summary":"2400 spans, 2400 marks, 800 values, showing latest 1200"}
```
