# YiFPGA Studio Trace 使用说明

## 1. 定位

YiFPGA Studio Trace 是 Debug Protocol v1 上的过程级事件扩展，用来观察 FPGA 内部过程级事件：什么时候开始、什么时候结束、哪里出现 warning/error/timeout，以及关键低频计数的变化。

Trace 适合：

- Frame、DMA、FIFO、IRQ 等流程时间线。
- descriptor、frame_id、fifo_level 等少量上下文参数。
- 异常路径定位，例如 timeout、overflow、drop。

Trace 不适合：

- 连续波形采样，仍建议使用 ILA 或后续 Logic Analyzer。
- 高吞吐性能统计和延迟直方图，这些归入后续 Profiler。
- PC 到 FPGA 的寄存器读写或控制命令，这些归入第三阶段 Monitor。

## 2. 协议消息

Trace 复用 Debug Protocol v1 帧格式：

```text
SOF + VERSION + TYPE + LEN + PAYLOAD + XOR_CHECKSUM
```

新增类型：

| Type | 名称 | Payload |
| --- | --- | --- |
| `0x10` | `TRACE_SPAN_BEGIN` | `u32 timestamp, u16 trace_id, u16 instance_id, u32 arg0` |
| `0x11` | `TRACE_SPAN_END` | `u32 timestamp, u16 trace_id, u16 instance_id, u8 status, u32 arg0` |
| `0x12` | `TRACE_MARK` | `u32 timestamp, u16 trace_id, u8 level, u32 arg0` |
| `0x13` | `TRACE_VALUE` | `u32 timestamp, u16 trace_id, u16 value_id, u32 value` |
| `0x14` | `TRACE_DROP` | `u32 timestamp, u16 trace_id, u32 drop_count` |

多字节字段为 little-endian。详细协议见 `doc/YiFPGA_Debug_Protocol_v1.md`。

常用语义：

| 常量 | 含义 |
| --- | --- |
| `trace_id = 0x0001` | DMA |
| `trace_id = 0x0002` | Frame |
| `trace_id = 0x0003` | FIFO |
| `trace_id = 0x0004` | Interrupt |
| `status = 0` | OK |
| `status = 1` | WARN |
| `status = 2` | ERROR |
| `status = 3` | TIMEOUT |

## 3. RTL 接入

用户工程通常实例化 `yifpga_debug_top`，并把 Trace 输入接到业务逻辑或 probe 输出。

核心输入分五组，均为单周期脉冲：

```verilog
trace_span_begin_valid
trace_span_begin_trace_id
trace_span_begin_instance_id
trace_span_begin_arg0

trace_span_end_valid
trace_span_end_trace_id
trace_span_end_instance_id
trace_span_end_status
trace_span_end_arg0

trace_mark_valid
trace_mark_trace_id
trace_mark_level
trace_mark_arg0

trace_value_valid
trace_value_trace_id
trace_value_id
trace_value_data

trace_drop_valid
trace_drop_trace_id
trace_drop_count
```

接入建议：

- `SPAN_BEGIN` 和 `SPAN_END` 使用相同的 `trace_id + instance_id`，Viewer 会据此合成完整 span。
- `arg0` 放一项最有诊断价值的上下文，例如 `frame_id`、`desc_id` 或 `fifo_level`。
- `TRACE_VALUE` 做低频采样，不要每拍发送。
- 同周期多类 Trace 事件需要上层 mux 或 pending flag 错峰发送，避免低优先级事件被丢弃。
- 如果 `drop_count` 增长，优先降低 Trace 频率、提高 `UART_BAUD` 或增大 `BUFFER_ADDR_WIDTH`。

## 4. 典型 Probe

第二阶段提供四类 probe，可直接参考或复用：

| 文件 | 用途 |
| --- | --- |
| `rtl/yifpga_debug/yifpga_trace_dma_probe.v` | DMA start/done/error/timeout 转 span 和 mark |
| `rtl/yifpga_debug/yifpga_trace_frame_probe.v` | Frame start/end/drop 转 span 和 mark |
| `rtl/yifpga_debug/yifpga_trace_fifo_probe.v` | FIFO level/almost_full/overflow 转 value 和 mark |
| `rtl/yifpga_debug/yifpga_trace_irq_probe.v` | IRQ assert/clear 边沿转 mark |

Probe 只做边沿检测和字段映射，不承担复杂业务状态机。复杂的节流、优先级和实例号分配建议留在用户逻辑中。

## 5. Viewer 使用

打开：

```text
tools/viewer/web/index.html
```

使用 Chrome 或 Edge。没有硬件时可点击 `Inject Sample`，Trace 视图会注入 Frame、DMA、FIFO、Interrupt、timeout 和 drop 样例。

连接硬件时：

1. 下载包含 `yifpga_debug_board_demo` 的 bitstream。
2. 将 FPGA `uart_tx` 接到 PC 串口 RX，并确认共地。
3. 在 Viewer 中选择与 RTL 一致的 baud rate，板级 demo 默认 `115200`。
4. 点击 `Connect`，切换到 `Trace` 视图。

Trace 视图提供：

- 按 `trace_id` 分泳道的 span/mark 时间线。
- span 详情，包括起止时间、duration、status、arg0 和 orphan 状态。
- Latest Values 表格，显示每组 `trace_id/value_id` 的最新值。
- problem/status/time range 过滤。
- JSONL 导出，包含 `trace_span`、`trace_open_span`、`trace_mark`、`trace_value`、`trace_drop`。

## 6. 验收命令

PC parser 回归：

```powershell
python tools\viewer\protocol_parser_test.py
```

Web Viewer 性能冒烟：

```powershell
python tools\viewer\web\run_perf_test.py
```

M9 Trace Adapter 仿真：

```powershell
xvlog -i rtl\yifpga_debug rtl\yifpga_debug\yifpga_trace_pkg.vh rtl\yifpga_debug\yifpga_trace_adapter.v sim\yifpga_debug\tb_yifpga_trace_adapter.v
xelab tb_yifpga_trace_adapter -s tb_yifpga_trace_adapter_sim
xsim tb_yifpga_trace_adapter_sim -runall
```

M10 board demo 仿真：

```powershell
xvlog -d YIFPGA_DEBUG_SIM -i rtl\yifpga_debug rtl\yifpga_debug\yifpga_debug_pkg.vh rtl\yifpga_debug\yifpga_trace_pkg.vh rtl\yifpga_debug\yifpga_debug_timestamp.v rtl\yifpga_debug\yifpga_debug_ring_buffer.v rtl\yifpga_debug\yifpga_debug_packetizer.v rtl\yifpga_debug\yifpga_debug_uart_tx.v rtl\yifpga_debug\yifpga_trace_adapter.v rtl\yifpga_debug\yifpga_trace_dma_probe.v rtl\yifpga_debug\yifpga_trace_frame_probe.v rtl\yifpga_debug\yifpga_trace_fifo_probe.v rtl\yifpga_debug\yifpga_trace_irq_probe.v rtl\yifpga_debug\yifpga_debug_core.v rtl\yifpga_debug\yifpga_debug_top.v rtl\board\yifpga_debug_board_demo.v sim\board\tb_yifpga_debug_board_demo.v
xelab tb_yifpga_debug_board_demo -s tb_yifpga_debug_board_demo_m10_sim
xsim tb_yifpga_debug_board_demo_m10_sim -runall
```

Vivado RTL elaboration：

```powershell
vivado -mode batch -source prj/scripts/check_yifpga_trace_m10_elab.tcl
```

## 7. 调试建议

- Trace 时间线没有 span：先确认是否有 `TRACE_SPAN_BEGIN/END` 帧，再检查 `trace_id + instance_id` 是否一致。
- span 显示 orphan：通常是漏发 begin、begin 被丢弃，或 end 的 instance_id 不一致。
- Viewer 卡顿：先限制显示窗口或降低 Trace 事件频率，再考虑提高串口波特率。
- checksum error 增长：优先检查 baud rate、接线方向、电平和共地。
- `drop_count` 增长：说明 Debug Core 或 Trace Adapter 出现竞争/背压，需要节流或增大缓冲。
