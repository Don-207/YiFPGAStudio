# YiFPGA Studio JTAG Transport 使用说明

## 启动与连接

硬件无关演示：

```bash
just m34-mock
```

FT232H 真板 Bridge（会访问并独占 cable，运行前需用户明确确认）：

```bash
just m35-ftdi-bridge
```

打开 `tools/viewer/web/index.html`，将 Source 设为 `JTAG Bridge`，默认 Host 为
`127.0.0.1`、Port 为 `48535`，然后 Connect。Viewer 通过 Bridge 的本地 WebSocket
接收 M34 socket record，DATA payload 不重编码，直接进入与 Serial 相同的 Debug
Protocol Parser 和 Debug、Trace、Profiler、Logic Analyzer 模型。

一次只连接一种数据源。`UART_AND_JTAG` 是板端独立对比模式，Viewer 不会把两路无标识
合并。JTAG Transport v1 仅支持 FPGA 到 Host；Monitor/LA 控制命令请切回 Serial。

## 状态与恢复

Transport 面板显示 Bridge/Transport 版本、稳定 target、session/build id、当前和平均吞吐、
buffer used、overflow、dropped bytes、reconnect 和最近错误。

连接断开不会删除已解析记录。重连 hello 或 SESSION record 表明 session 改变时，Viewer
只清除 Parser 半帧，从下一个 `0xA5` SOF 恢复，避免跨 session 拼帧。Bridge 的客户端发送
队列固定为 64 条；慢客户端会被断开，不以无界缓存隐藏积压。

## Raw capture 与回放

```bash
python3 tools/jtag/yifpga_jtag_bridge.py --capture capture.bin
```

`capture.bin` 是 Parser 原始 byte stream，旁路的 `capture.bin.jsonl` 记录时间、session、起始
计数和块长。在 Viewer 的 Raw replay 文件框选择 `.bin` 可离线送入同一 Parser。若 capture
跨多个 session，应按 jsonl 的 session 边界拆分后分别回放，裸 `.bin` 本身不含 session 标记。

## 配置与性能结论

- 真板推荐：实际 10 MHz TCK、512 B block、10 ms idle polling、Bridge 每 1 s 发布状态、
  64-record 客户端队列；专用持续源 1 MiB 窗口测得约 232.8 KiB/s。
- 保守：6 MHz TCK、256 B block、10 ms idle polling；适合对 cable 信号裕量更保守的诊断，
  但当前实测约 83.4 KiB/s，不能作为达到发布吞吐门槛的配置。
- Mailbox v1 最大 block 是 1 KiB；2 KiB/4 KiB 必须等 ABI capability/version 扩展，不能用
  Host 拼批伪装成单次 JTAG block。
- FPGA USER-DR payload shift 已通过 Direct FTDI 真板路径验证，短窗口 256 B 请求曾达到
  约 151.89 KiB/s；这不是持续门槛结论。正式结论仍需高速持续数据源下记录 TCK、P50/P99、
  CPU、BRAM occupancy 和 256/512/1024 B 对比，并完成长稳测试。Mock 结果只用于正确性与
  有界队列回归，不作为发布吞吐结论。

专用性能镜像流程：

```bash
just m35-perf-source-sim
just m35-perf-bitstream
just m35-perf-program '*210512180081*'
python3 tools/jtag/benchmark_m34_board.py --sizes 256,512,1024 --bytes 1048576 --tck-hz 10000000
```

## 回归

```bash
just m35-check
```

该门禁覆盖 socket record 拆分/粘连、WebSocket binary framing、session reset、慢客户端有界
断开、连续块字节等价、共享 Parser fixture，以及 Viewer 既有压力回归。命令不访问 cable，
不启动 Vivado。
