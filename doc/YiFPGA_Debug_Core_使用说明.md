# YiFPGA Studio Debug Core 使用说明

## 1. 适用范围

本文说明 YiFPGA Studio Debug Core（原 `YiFPGA Debug Core`）的 RTL 接入方式。当前实现为 FPGA 到 PC 的单向 UART 调试链路，不包含 PC 到 FPGA 的寄存器读写或控制命令。

## 2. 文件清单

核心 RTL：

```text
rtl/yifpga_debug/yifpga_debug_pkg.vh
rtl/yifpga_debug/yifpga_debug_timestamp.v
rtl/yifpga_debug/yifpga_debug_ring_buffer.v
rtl/yifpga_debug/yifpga_debug_packetizer.v
rtl/yifpga_debug/yifpga_debug_uart_tx.v
rtl/yifpga_debug/yifpga_debug_core.v
rtl/yifpga_debug/yifpga_debug_top.v
```

板级 demo：

```text
rtl/board/yifpga_debug_board_demo.v
prj/constraints/yifpga_debug_board_demo.xdc
```

## 3. 顶层接口

用户工程实例化 `yifpga_debug_top`：

```verilog
yifpga_debug_top #(
    .CLK_FREQ_HZ(100000000),
    .UART_BAUD(115200),
    .BUFFER_ADDR_WIDTH(4)
) u_yifpga_debug (
    .clk(clk),
    .rst(rst),

    .heartbeat_valid(heartbeat_valid),
    .status_valid(status_valid),

    .event_valid(event_valid),
    .event_id(event_id),
    .event_level(event_level),
    .event_arg0(event_arg0),

    .watch_valid(watch_valid),
    .watch_id(watch_id),
    .watch_value(watch_value),

    .print_valid(print_valid),
    .print_id(print_id),
    .print_arg0(print_arg0),
    .print_arg1(print_arg1),

    .uart_tx(uart_tx),
    .busy(debug_busy),
    .buffer_used(buffer_used),
    .drop_count(drop_count),
    .packet_count(packet_count)
);
```

## 4. 输入消息

所有 `*_valid` 为单周期脉冲。当前仲裁优先级为：

```text
event > watch > debug_print > heartbeat > status
```

如果同一周期多个输入同时有效，只接受最高优先级消息，其余计入 `drop_count`。用户逻辑如果需要保证不丢低优先级消息，应像板级 demo 一样用 pending flag 错峰发送。

### Event

```text
event_valid
event_id[15:0]
event_level[7:0]
event_arg0[31:0]
```

用于状态切换、中断、错误、帧边界等离散事件。

### Watch

```text
watch_valid
watch_id[15:0]
watch_value[31:0]
```

用于周期性或变化时上报一个观测值。Viewer 会按 `watch_id` 合并显示最新值。

### Debug Print

```text
print_valid
print_id[15:0]
print_arg0[31:0]
print_arg1[31:0]
```

FPGA 不做字符串格式化。第一阶段由 Viewer 显示 `print_id + arg0 + arg1`，后续可用配置文件把 `print_id` 映射成文本模板。

### Heartbeat / Status

```text
heartbeat_valid
status_valid
```

`HEARTBEAT` 只携带 timestamp。`STATUS` 携带 `buffer_used/drop_count/packet_count`。建议低频周期性发送。

## 5. 参数建议

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `CLK_FREQ_HZ` | 依工程设置 | UART 分频和时间戳换算基准 |
| `UART_BAUD` | `115200` | 与 Viewer 串口设置一致 |
| `BUFFER_ADDR_WIDTH` | `4` | ring buffer 深度为 `2^BUFFER_ADDR_WIDTH` |

若高频 watch 或 event 导致 `drop_count` 增长，可优先：

- 提高 `UART_BAUD`，例如 `921600` 或 `1000000`。
- 降低 watch/status 上报频率。
- 增大 `BUFFER_ADDR_WIDTH`。

## 6. 板级 demo 说明

`yifpga_debug_board_demo` 顶层提供：

- `clk_p/clk_n`：100 MHz 差分输入。
- `reset_n`：低有效复位。
- `demo_trigger`：上升沿额外触发 event 和 debug print。
- `uart_tx`：连接 PC 串口 RX。
- `led0`：heartbeat 闪烁。
- `led1`：event 脉冲，`drop_count != 0` 后常亮报警。

当前 KU5P 板卡约束来自厂家 `pin.xdc`，已经固化在：

```text
prj/constraints/yifpga_debug_board_demo.xdc
```

## 7. 已知限制

- payload 最大 32 字节。
- checksum 为 XOR，不是 CRC-8。
- `drop_count/packet_count` 为 16 bit，长时间运行可能回绕。
- 只支持 FPGA 到 PC 单向传输。
- timestamp 为 32 bit tick，100 MHz 下约 42.95 秒回绕。
