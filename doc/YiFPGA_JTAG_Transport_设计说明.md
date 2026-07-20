# YiFPGA Studio JTAG Transport 设计说明

## 1. 范围

JTAG Transport v1 将完整、未经重编码的 YiFPGA Studio Debug Protocol v1 byte stream 从 FPGA 搬运到 Host。Transport 不解析业务帧。P0 仅定义 FPGA 到 Host 数据面；Monitor/LA 反向控制留作 P1。

```text
Debug Packetizer -> Transport Router -> BRAM Ring Buffer -> JTAG Mailbox
                                                            |
                                                     Host Bridge -> TCP -> Qt
```

## 2. Transport 接口

FPGA 输入采用 `data[7:0] + valid + ready`。一次传输发生在同一时钟沿的 `valid && ready`。复位后 `valid` 的生产者不得依赖 JTAG 是否连接。

构建模式：

| 模式 | UART | JTAG | 规则 |
| --- | --- | --- | --- |
| `UART` | 开 | 关 | 行为与现有实现一致 |
| `JTAG` | 关 | 开 | 写入独立 JTAG 缓冲 |
| `UART_AND_JTAG` | 开 | 开 | 两路独立接收/丢弃，不共享背压 |
| JTAG disabled | 按原配置 | 裁剪 | 不实例化 BSCAN/BRAM |

双输出不得用公共 `ready` 等待两路。任一路满只更新该路 drop/overflow 统计。

## 3. Mailbox v1 ABI

所有整数为 little-endian。Header 总长 40 字节，按 4 字节对齐。

| 偏移 | 类型 | 字段 | 方向 | 复位值/语义 |
| ---: | --- | --- | --- | --- |
| `0x00` | u32 | `magic` | FPGA→Host | ASCII `OFJT`，内存字节 `4F 46 4A 54` |
| `0x04` | u16 | `transport_version` | FPGA→Host | `0x0001` |
| `0x06` | u16 | `capabilities` | FPGA→Host | v1 必选能力位 |
| `0x08` | u32 | `session_id` | FPGA→Host | reset 后变化，0 保留 |
| `0x0C` | u32 | `buffer_size` | FPGA→Host | 4/8/16/32/64 KB |
| `0x10` | u32 | `write_count` | FPGA→Host | 已接受字节的单调模计数 |
| `0x14` | u32 | `read_count` | 双向 | 已提交消费字节的单调模计数 |
| `0x18` | u32 | `available_bytes` | FPGA→Host | `(write-read) mod 2^32` |
| `0x1C` | u32 | `overflow_count` | FPGA→Host | 每次发生丢弃加 1 |
| `0x20` | u32 | `dropped_bytes` | FPGA→Host | 被拒绝字节数，模 `2^32` |
| `0x24` | u32 | `build_id` | FPGA→Host | 构建身份，0 表示未提供 |

能力位：

| Bit | 名称 | v1 |
| ---: | --- | --- |
| 0 | FPGA→Host | 必须为 1 |
| 1 | Block read | 必须为 1 |
| 2 | Drop newest | 必须为 1 |
| 3 | Session ID | 必须为 1 |
| 4..15 | 保留 | Host 忽略未知置位 |

Header 发布必须是一致快照；RTL 可使用握手快照或保证 Host 可检测并重读不一致快照。

## 4. Ring Buffer 与计数语义

- 默认缓冲 16 KB，允许 4/8/16/32/64 KB，均为 2 的幂。
- 物理地址为 `count & (buffer_size - 1)`。
- `write_count/read_count` 是 u32 模计数；距离计算为无符号 `(newer - older) mod 2^32`。
- 系统不允许未消费距离超过 `buffer_size`，因此距离无二义性。
- 满时采用 `drop newest`：旧数据和 `write_count` 不变，`overflow_count` 每次写事务加 1，`dropped_bytes` 按拒绝字节数增加。
- 计数器回绕不是 session reset，不得清空 Parser。

## 5. Host 事务

1. Discover 并显式选择 target/device/USER chain。
2. 读取 Header，校验 magic、version、必选能力、buffer size 和计数距离。
3. 若 `available_bytes == 0`，进入 idle polling，不发起数据读。
4. 读取 `min(available_bytes, configured_block_size)` 个字节；v1 block 范围 1..1024 字节。
5. 只有完整块到达 Host 后，提交 `read_count += block_length`。
6. 再读 Header，重复处理。

短读视为失败，不提交。重试读取同一 `read_count`。重复或迟到数据块可按 `(session_id,start_count,length)` 识别；已经提交的块不得二次提交。

## 6. Session、断线与错误

- FPGA/Transport reset 产生新的非零 `session_id`，并清零读写与统计计数。
- Host 发现 session 改变后丢弃所有在途事务和 Parser 半帧，从下一个 Debug Protocol `SOF=0xA5` 恢复。
- magic 错误、未知主版本、非法 buffer size、`available > buffer_size` 或计数不一致均禁止消费数据。
- 未知 capability 位应忽略；缺少 v1 必选能力则拒绝 attach。
- 断线重连后必须重新验证 target identity、Header 和 session。

## 7. 性能口径

- 有效吞吐：测试窗口内成功提交给统一 Parser 的 payload 字节数/秒，不含 JTAG/Header/TCP 开销。
- P50/P99 延迟：从 FPGA 字节进入 Transport 到 Host Bridge 交付该字节所在块的时间分位数。
- Host CPU：稳定测试窗口内 Bridge 进程 CPU 使用率。
- drop/overflow：使用 Mailbox 计数差值，不由 Host 推测。

固定 block 测试点为 256 B、512 B、1 KB、2 KB、4 KB；v1 P0 首版 ABI 最大 1 KB，2/4 KB 仅在后续 capability/version 扩展后启用。发布最低持续有效吞吐为 100 KB/s，500 KB/s–1 MB/s 为冲刺目标。

## 8. 可执行契约

参考实现位于 `tools/jtag/mailbox_model.py`，共享向量位于 `tools/jtag/fixtures/m32_mailbox_vectors.json`。M33 RTL 和 M34 Host Bridge 对边界行为有歧义时，以本说明和参考模型测试为准；ABI 变化必须提升 `transport_version`。
