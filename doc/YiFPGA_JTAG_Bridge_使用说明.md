# YiFPGA Studio JTAG Bridge 使用说明

## 离线验收

```bash
just m34-check
just m32-check
```

`m34-check` 不启动 Vivado、不访问 cable，覆盖 Mailbox fixture 字节等价、3000 个连续块、
session reset、三次身份复核重连、多目标拒绝和慢客户端有界断开。

## Mock Bridge

```bash
just m34-mock
```

默认监听原始 TCP `127.0.0.1:48534`，并为 Web Viewer 监听 WebSocket
`127.0.0.1:48535`。监听地址必须显式修改才会超出 loopback；可用
`--port` 和 `--websocket-port` 分别修改端口。

## Socket 协议

每条记录为：

```text
u8 type | u32le payload_length | payload
```

- `1`：JSON hello，包含 bridge/transport 版本、稳定目标身份和 session。
- `2`：未经修改的 Debug Protocol payload。
- `3`：JSON status，默认每秒发布一次。
- `4`：JSON session change；Viewer 收到后应清除半帧状态并等待下一个 SOF。
- `5`：保留给结构化错误。

慢客户端队列默认上限为 64 条记录；队列满时断开该客户端，不无限增长内存。

## Raw capture

```bash
python3 tools/jtag/yifpga_jtag_bridge.py --capture capture.bin
```

`capture.bin` 仅保存原始 payload；`capture.bin.jsonl` 保存时间、session、逻辑起始计数和块长。

## Direct FTDI backend（推荐真板路径）

M34 已验证的 FT232H/MPSSE USER2 scanner 已接入常驻 Bridge：

```bash
just m35-ftdi-bridge
# 参数化示例
just m35-ftdi-bridge tck=12000000 block=512
```

默认 VID/PID 为 `0403:6014`、USER2、build ID `0x4D340001`、TCK 约 6 MHz。
也可直接使用 `--ftdi-vendor`、`--ftdi-product`、`--build-id`、`--tck-hz` 和
`--block-size`。FTDI 简化枚举按配置产生一个候选身份；`open` 会通过真实 Mailbox Header
复核 magic、ABI 和 build ID 后才允许消费 payload。

Payload DR 完整 UPDATE 是硬件 commit 边界，因此 backend 在下一次 Header 扫描核对
`read_count`，不为每块增加额外验证往返。真板运行会独占 FTDI 设备，必须先关闭 Vivado
Hardware Manager 对同一 cable 的连接。

## Xilinx Hardware Manager backend 状态

```bash
python3 tools/jtag/yifpga_jtag_bridge.py --backend xilinx --list-targets
```

Python/Vivado 常驻进程、目标枚举、显式选择、结构化错误和退出清理已经实现。FPGA 端
`BSCANE2` USER-DR 命令引擎及真实 payload shift 已通过 Direct FTDI 路径验证；缺口仅在
Vivado Hardware Manager Tcl 没有可移植的任意 USER data-register raw shift 命令。因此当前
`yifpga_jtag_read.tcl` 会明确报错，不会提交或伪造数据。真板 Bridge 应使用 Direct FTDI
backend，或另行评估 XSDB/XVC/正式 API。

Mailbox RTL 已使用“工作读指针/提交读指针”分离事务：payload 读取只推进工作指针，完整
USER-DR 扫描后的 `payload_commit` 才更新公开 `read_count`；扫描中止通过 `payload_abort`
回退。这两个信号是后续 BSCAN 命令状态机必须驱动的事务边界。

## USER-DR 扫描协议

USER chain 默认为 `USER2`。每个操作使用两次 LSB-first DR scan：第一次发送 32-bit 命令，
第二次读取响应。

```text
命令 byte 0: 0xA6
命令 byte 1: 0x01=Header，0x02=Payload
命令 byte 2..3: u16le 响应字节数
```

Header 长度固定为 40；Payload 长度为 1..1024。Payload 响应扫描只有在位数严格等于
`length * 8` 时才在 UPDATE 提交。短扫或长扫均产生 abort，公开 `read_count` 不变。

完整 Xilinx 集成模块为 `yifpga_jtag_transport_xilinx`。综合门禁检查一个 `BSCANE2`、
一个 USER-DR 引擎及至少一个 `RAMB*`；默认 4 KiB 配置实测映射为一个 `RAMB36E2`。
