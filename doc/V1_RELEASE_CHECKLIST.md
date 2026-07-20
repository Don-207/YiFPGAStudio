# YiFPGA Studio v1.0.0 发布 Checklist

本清单用于将当前候选版本收口为正式 `v1.0.0`。除特别标注外，所有命令均从仓库根目录
运行。Vivado 构建、bitstream 生成和板卡操作必须由具备目标硬件访问权限的发布负责人
显式执行，不属于自动 CI。

## 1. 源码与仓库

- [ ] 工作树干净，发布提交已完成代码审查。
- [x] README、Changelog、贡献指南和安全策略与 v1.0.0 一致。
- [x] 使用 `prj/create_project.tcl` 在全新目录成功重建工程，确认不依赖开发者机器的绝对路径。
- [x] 仓库不包含 `.bit`、`.dcp`、`.ltx`、运行目录、凭据或未脱敏采集数据。
- [ ] GitHub Actions `Release Check` 在发布提交上通过。

本地无硬件门禁：

```bash
just release-check
```

预期：命令退出码为 0；协议、Viewer、AI Debug、JTAG mailbox/bridge 测试全部显示
`PASS` 或 `OK`。该命令不调用 Vivado、不生成硬件镜像、不访问板卡。

## 2. 工具与目标确认

- [x] 记录 Python、Node.js 和 just 版本：Python 3.10.12、Node.js v20.20.2、just 1.56.0。
- [x] 记录 Vivado 完整版本及补丁级别；当前基线为 2024.2 Build 5239630。
- [x] 确认目标器件为 `xcku5p-ffvb676-2-i`。
- [x] 复核 `prj/constraints/yifpga_debug_board_demo.xdc` 与 ATK-KU5 实际板卡引脚、电平和时钟一致。
- [x] 记录板卡 ATK-KU5、JTAG target `Digilent/210512180081` 和串口设备路径。

## 3. Vivado 静态与综合门禁

执行前确认磁盘空间足够，并预留多配置综合时间。以下命令执行五种配置的 Vivado 综合，
不生成 bitstream，也不烧录板卡：

```bash
just release-matrix
```

检查 `prj/YiFPGAStudio.runs/m36_matrix/<configuration>/` 中每种配置的：

- [x] `manifest.txt` 中器件、功能开关和 BSCANE2 数量符合预期。
- [x] `utilization.rpt` 无异常资源增长。
- [x] `clock_interaction.rpt` 和 `cdc.rpt` 已审查且风险可接受。

## 4. 实现与发布镜像

以下命令执行综合、实现、布局布线并生成 normal 模式的 bitstream 和 ILA probes；可能耗时
较长，但不会自动烧录板卡：

```bash
just release-bitstream
```

预期产物位于 `prj/YiFPGAStudio.runs/m36_ila/`：

- `yifpga_debug_board_demo_m36_ila.bit`
- `yifpga_debug_board_demo_m36_ila.ltx`
- `manifest.txt`
- `route_status.rpt`
- `timing_summary.rpt`
- `drc.rpt`
- `utilization.rpt`
- `cdc.rpt`

- [x] `manifest.txt` 中 `wns_ns` 非负，BSCANE2 和 ILA 数量均为 1。
- [x] 无未布线网络。
- [x] Timing Summary 满足时序要求。
- [x] DRC、CDC 和资源报告已人工审查。
- [x] 记录 `.bit`、`.ltx` 和发布提交的 SHA-256。

## 5. 烧录与实板验证

以下命令会连接 Vivado Hardware Manager，并改写匹配板卡的 FPGA 配置。必须把
`<exact-target>` 替换为预先记录且唯一匹配的 cable target：

```bash
just release-program <exact-target>
```

若发布主机只连接了一个 JTAG target，也可使用自动唯一目标模式；枚举到 0 个或多个 target
时脚本必须拒绝烧录：

```bash
just release-program-auto
```

- [x] 命令只匹配一个 target 和一个 FPGA。
- [x] 烧录成功，且恰好枚举一个 ILA。
- [x] UART 在 `115200 8N1` 下持续输出有效 Debug Protocol 帧。
- [x] Web Viewer 的 Debug、Trace、Monitor、Profiler、Logic Analyzer 和 AI Debug 基本流程通过。
- [x] Monitor 写操作只使用可恢复测试值，并确认恢复原值。
- [x] 断开/重连 JTAG Bridge 后数据流恢复，无新增 drop/overflow。

normal Bridge 和 UART 冒烟命令：

```bash
just release-jtag-smoke
just release-uart-validate <serial-device> 30 50 prj/YiFPGAStudio.runs/release/uart_capture.bin
just release-monitor-safe <serial-device>
```

normal 镜像用于功能和低速稳定性验证，不承担 100,000 B/s 性能门禁。性能门禁使用
`jtag_perf` 连续数据源镜像：

```bash
just release-perf-bitstream
just release-perf-program-auto
just release-perf-bridge
```

Bridge 启动后，另开终端执行 30 分钟性能 soak：

```bash
just release-soak 1800 3 prj/YiFPGAStudio.runs/m36/m36_perf_soak.csv
```

- [x] 平均吞吐为 154,193.906 B/s，不低于 100,000 B/s。
- [x] `last_error` 为空（normal 镜像 1,800 秒 soak）。
- [x] drop/overflow 计数在验证窗口内不增长（normal 镜像 1,800 秒 soak）。
- [x] 三次客户端重连均成功（normal 镜像 1,800 秒 soak）。
- [x] 保存 soak CSV、Bridge 日志和异常说明。

## 6. 发布

- [x] 将 `CHANGELOG.md` 的 `Unreleased` 内容转为 `1.0.0` 并填写发布日期。
- [x] README 不再将版本描述为候选版本。
- [ ] 确认所有报告和验证记录可追溯到同一个提交。
- [ ] 在该提交上创建带注释的 `v1.0.0` tag。
- [ ] 推送分支和 tag，并创建 GitHub Release。
- [ ] Release Notes 明确只支持当前 Xilinx 参考平台及已知限制。
- [ ] 如发布 bitstream，同时提供对应 `.ltx`、目标板卡说明和 SHA-256；不要把产物提交进 Git。
