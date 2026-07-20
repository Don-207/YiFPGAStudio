# YiFPGA Studio Profiler 使用说明

## 1. 功能范围

第四阶段 Profiler 在 board demo 中提供四类指标：

| metric_id | 名称 | value0 | value1 | value2 | value3 |
| --- | --- | --- | --- | --- | --- |
| `0x0001` | `AXIS_DEMO_THROUGHPUT` | bytes/window | beats | active cycles | stall cycles |
| `0x0101` | `FIFO_DEMO_LEVEL` | current level | max level | min level | overflow/underflow |
| `0x0201` | `DEMO_LATENCY` | completed count | min cycles | max cycles | average cycles |
| `0x0301` | `FRAME_RATE` | frame count | drop/error | min interval | max interval |

Profiler 帧复用 Debug Protocol v1：

- `0x30 PROFILER_SNAPSHOT`
- `0x31 PROFILER_ALERT`

## 2. Monitor 寄存器

| 地址 | 名称 | 属性 | 说明 |
| --- | --- | --- | --- |
| `0x0040` | `PROFILER_ID` | RO | 固定值 `0x4F465034` |
| `0x0044` | `PROFILER_VERSION` | RO | Profiler 版本 |
| `0x0048` | `PROFILER_CONTROL` | RW | bit0 为 enable |
| `0x004C` | `PROFILER_SAMPLE_PERIOD` | RW | snapshot 窗口周期，单位为 clock cycle |
| `0x0050` | `PROFILER_CLEAR` | TRIGGER | 写非零值清零当前统计窗口 |
| `0x0054` | `PROFILER_STATUS` | RO/W1C | bit0 overflow/alert，bit1 debug drop，bit2 profiler backpressure |
| `0x0058` | `PROFILER_METRIC_MASK0` | RW | demo metric 使能位，bit1/2/3/4 对应四类 metric |
| `0x005C` | `PROFILER_ALERT_THRESHOLD0` | RW | demo FIFO/latency 阈值，写 0 关闭阈值告警 |

## 3. Web Viewer 操作

1. 连接 UART。
2. 在 Monitor 视图读取 `PROFILER_ID` 和 `PROFILER_VERSION`。
3. 写 `PROFILER_SAMPLE_PERIOD`，例如 `100000`。
4. 写 `PROFILER_CONTROL = 1` 启用。
5. 切到 Profiler 视图观察四类 metric、趋势图和 alert 面板。
6. 写 `PROFILER_CLEAR = 1` 后，统计窗口重新开始。
7. 写 `PROFILER_ALERT_THRESHOLD0` 为较低值可触发 demo alert。

## 4. 仿真与 Elaboration

```powershell
xvlog -d YIFPGA_DEBUG_SIM -i rtl\yifpga_debug rtl\yifpga_debug\yifpga_debug_pkg.vh rtl\yifpga_debug\yifpga_trace_pkg.vh rtl\yifpga_debug\yifpga_monitor_pkg.vh rtl\yifpga_debug\yifpga_profiler_pkg.vh rtl\yifpga_debug\yifpga_debug_timestamp.v rtl\yifpga_debug\yifpga_debug_ring_buffer.v rtl\yifpga_debug\yifpga_debug_packetizer.v rtl\yifpga_debug\yifpga_debug_uart_tx.v rtl\yifpga_debug\yifpga_debug_uart_rx.v rtl\yifpga_debug\yifpga_debug_command_parser.v rtl\yifpga_debug\yifpga_trace_adapter.v rtl\yifpga_debug\yifpga_trace_dma_probe.v rtl\yifpga_debug\yifpga_trace_frame_probe.v rtl\yifpga_debug\yifpga_trace_fifo_probe.v rtl\yifpga_debug\yifpga_trace_irq_probe.v rtl\yifpga_debug\yifpga_monitor_reg_bank.v rtl\yifpga_debug\yifpga_monitor_core.v rtl\yifpga_debug\yifpga_monitor_adapter.v rtl\yifpga_debug\yifpga_profiler_counter.v rtl\yifpga_debug\yifpga_profiler_core.v rtl\yifpga_debug\yifpga_profiler_adapter.v rtl\yifpga_debug\yifpga_profiler_axis_probe.v rtl\yifpga_debug\yifpga_profiler_fifo_probe.v rtl\yifpga_debug\yifpga_profiler_frame_probe.v rtl\yifpga_debug\yifpga_profiler_latency.v rtl\yifpga_debug\yifpga_debug_core.v rtl\yifpga_debug\yifpga_debug_top.v rtl\board\yifpga_debug_board_demo.v sim\board\tb_yifpga_debug_board_profiler.v
xelab tb_yifpga_debug_board_profiler -s tb_yifpga_debug_board_profiler_sim
xsim tb_yifpga_debug_board_profiler_sim -runall
```

```powershell
vivado -mode batch -source prj/scripts/check_yifpga_profiler_m21_elab.tcl
```
