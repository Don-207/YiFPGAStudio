# YiFPGA Studio Profiler Probe Integration Notes

M19 adds four reusable profiler probes that expose the same metric shape used by
the M18 profiler path:

```verilog
metric_valid
metric_id
metric_value0
metric_value1
metric_value2
metric_value3
metric_overflow
```

## AXI Stream Probe

`yifpga_profiler_axis_probe` observes `valid/ready/keep/last`.

- `value0`: transferred bytes by default, or words when `COUNT_BYTES=0`
- `value1`: handshake beat count
- `value2`: active cycles, `valid || ready`
- `value3`: stall cycles

`STALL_MODE=0` counts source stalls (`valid && !ready`), `STALL_MODE=1` counts
sink idle cycles (`ready && !valid`), and `STALL_MODE=2` counts either case.

## FIFO Probe

`yifpga_profiler_fifo_probe` tracks a clear-delimited FIFO window.

- `value0`: current level
- `value1`: window maximum level
- `value2`: window minimum level
- `value3`: `{overflow_count, underflow_count}`

Use `clear` at the profiler sample boundary when the next window should start.

## Frame Probe

`yifpga_profiler_frame_probe` tracks completed, dropped, and errored frames.

- `value0`: completed frame count
- `value1`: `{drop_count, error_count}`
- `value2`: minimum inter-frame interval in clock cycles
- `value3`: maximum inter-frame interval in clock cycles

`metric_overflow` is asserted for drop or error events so the profiler core can
promote the sample to an alert.

## Latency Probe

`yifpga_profiler_latency` supports one outstanding transaction.

- `value0`: completed transaction count
- `value1`: minimum latency
- `value2`: maximum latency
- `value3`: average latency on normal completion

If `start_valid` arrives while already busy, the probe reports a busy overflow.
If `timeout_clear` is asserted, or `TIMEOUT_CYCLES` is nonzero and expires, the
probe clears the outstanding transaction and reports a timeout overflow. During
busy or timeout events `value3` is `{busy_count, timeout_count}`.

## DDR And PCIe Hook Points

Keep high-speed counters in their local clock domain first, then hand the debug
domain a stable snapshot or CDC-safe event stream.

- DDR: command accepted, read/write data beat, busy, stall, and error events.
- PCIe: posted write bytes, completion bytes, request pending, retry/error, and
  backpressure events.
- Bus width byte counters should be parameterized, normally `DATA_WIDTH / 8`.
- Multi-clock integrations should avoid sampling raw level or valid signals
  directly from the debug clock domain.
