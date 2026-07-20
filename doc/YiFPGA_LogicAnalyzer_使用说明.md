# YiFPGA Studio Logic Analyzer 使用说明

## P0 能力

当前 Logic Analyzer 集成顶层为 `yifpga_debug_board_demo`。采样宽度固定为 32 bit，默认最大深度为
128 samples。Viewer 通过 Monitor UART 寄存器窗口配置、arm、force trigger、clear 和 start readout。

## Monitor Register Map

| 地址 | 名称 | 属性 |
| --- | --- | --- |
| `0x0060` | `LA_ID` | RO，`0x4F464C41` |
| `0x0064` | `LA_VERSION` | RO |
| `0x0068` | `LA_CONTROL` | RW，bit0 enable，bit1 auto_readout，bit2 trigger_enable |
| `0x006C` | `LA_STATUS` | RO/W1C，`[2:0] state`，bit3 done，bit4 overflow，bit5 config_error，bit6 readout_busy，bit7 tx_backpressure，`[15:8] error_code` |
| `0x0070` | `LA_SAMPLE_DIVISOR` | RW，0 被拒绝 |
| `0x0074` | `LA_CAPTURE_DEPTH` | RW，1..128 |
| `0x0078` | `LA_PRETRIGGER_DEPTH` | RW，小于 capture depth |
| `0x007C` | `LA_TRIGGER_MODE` | RW，0 disabled，1 level，2 rising，3 falling，4 mask match |
| `0x0080` | `LA_TRIGGER_CHANNEL` | RW，0..31 |
| `0x0084` | `LA_TRIGGER_VALUE` | RW |
| `0x0088` | `LA_TRIGGER_MASK` | RW |
| `0x008C` | `LA_COMMAND` | WO trigger，bit0 arm，bit1 stop，bit2 clear，bit3 force_trigger，bit4 start_readout |
| `0x0090` | `LA_CAPTURE_ID` | RO |
| `0x0094` | `LA_CHANNEL_MASK` | RW |

## P0 Channel Manifest

| bit | 名称 |
| --- | --- |
| `0` | `uart_tx_busy` |
| `1` | `uart_rx_valid` |
| `2` | `debug_tx_valid` |
| `3` | `debug_tx_ready` |
| `4` | `trace_valid` |
| `5` | `monitor_resp_valid` |
| `6` | `profiler_snapshot_valid` |
| `7` | `demo_frame_tick` |
| `15:8` | `debug_buffer_used_lsb` |
| `23:16` | `demo_fifo_level_lsb` |
| `26:24` | `la_state_debug` |
| `27` | `la_overflow` |
| `28` | `la_config_error` |
| `29` | `la_readout_busy` |

## Typical Flow

1. Read `LA_ID` and `LA_VERSION`.
2. Write sample divisor, capture depth, pretrigger depth, trigger mode/channel/value/mask.
3. Write `LA_CONTROL = 0x5` to enable capture and trigger matching.
4. Write `LA_COMMAND = 0x1` to arm.
5. Wait for trigger or write `LA_COMMAND = 0x8` to force trigger.
6. Poll `LA_STATUS.done`, then write `LA_COMMAND = 0x10` to start readout.
7. Viewer receives `LA_CAPTURE_HEADER`, optional `LA_TRIGGER_EVENT`, one or more `LA_SAMPLE_DATA` chunks, and `LA_CAPTURE_STATUS`.
8. Write `LA_COMMAND = 0x4` to clear.

## Notes

LA readout shares the UART TX path with Monitor, Trace and Profiler frames. Monitor responses have highest priority; LA readout is finite and is prioritized ahead of continuous Trace/Profiler traffic so a user-requested capture cannot starve. Keep capture depth modest at low UART baud rates; 32 to 128 samples is the intended P0 range.

This RTL LA complements vendor ILA. It is controllable through the same UART Debug/Monitor path as the Viewer, but it has lower bandwidth and a smaller fixed sample buffer than on-chip vendor debug cores.

## M26 Validation Commands

先执行不访问硬件的验证器自测：

```text
python tools/viewer/logic_analyzer_validate.py --self-test
```

确认串口和板卡状态后执行真实链路验证：

```text
python tools/viewer/logic_analyzer_validate.py --port COM7 --baud 115200
```

验证器使用 force trigger 建立确定性闭环，并检查寄存器读回、capture done、header/data/status 帧和 capture ID 递增。Viewer 显示以及 VCD/JSONL 文件内容需要按 M26 验证记录人工确认。
