# YiFPGA Studio Monitor 使用说明

## 功能

YiFPGA Studio Monitor 在 Debug Protocol v1 上增加 PC 到 FPGA 的安全控制通道。第一版支持：

- `MONITOR_READ_REQ/RESP`
- `MONITOR_WRITE_REQ/RESP`
- 静态寄存器 map
- RO/RW/W1C/TRIGGER 权限检查

## 寄存器

| 地址 | 名称 | 权限 | 说明 |
| --- | --- | --- | --- |
| `0x0000` | `MONITOR_ID` | RO | 固定 `0x4F464D30` |
| `0x0004` | `MONITOR_VERSION` | RO | Monitor RTL 版本 |
| `0x0008` | `CONTROL` | RW | demo 控制位 |
| `0x000C` | `LED_CONTROL` | RW | `bit0/bit1` 控制板级 LED |
| `0x0010` | `DEMO_PERIOD` | RW | Event/Trace demo 周期，禁止写 0 |
| `0x0014` | `COUNTER0` | RO | demo 自增计数器 |
| `0x0018` | `CLEAR_COUNTERS` | TRIGGER | 写 1 产生清零脉冲 |
| `0x001C` | `ERROR_STATUS` | W1C | 写 1 清对应错误位 |

## Viewer 操作

1. 使用 Chrome 或 Edge 打开 `tools/viewer/web/index.html`。
2. 选择与 RTL 一致的 baud rate。
3. 连接 FPGA `uart_tx` 到 PC RX，PC TX 到 FPGA `uart_rx`，并共地。
4. 点击 Monitor 表格中的 `Read` 读取寄存器。
5. 对 RW/W1C 寄存器填写 value 和 mask 后点击 `Write`，确认后发送。
6. 对 TRIGGER 寄存器点击 `Trigger`。
7. 可启用 Poll 周期读取寄存器。

## 板级约束

当前工程已为 `uart_rx` 补充 `PACKAGE_PIN B16` 和 `IOSTANDARD LVCMOS18`。板级连接时请将 PC TX 接到 FPGA `uart_rx`，并确认与 PC RX/FPGA `uart_tx` 共地。
