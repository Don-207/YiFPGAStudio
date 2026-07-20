# YiFPGA Studio 剩余工作

本文记录从 OpenFPGA Studio 迁回独立仓库后的剩余收口项目。详细发布验收项见
[`V1_RELEASE_CHECKLIST.md`](V1_RELEASE_CHECKLIST.md)。

## 当前基线

截至 `main` 合并提交 `6c9b4cc`：

- 仓库已完成独立命名和 GitHub 迁移。
- 无硬件 `just release-check` 已在本地和 GitHub Actions 通过。
- GitHub Actions Viewer 测试已固定使用 Google Chrome。
- Vivado 工程已有 `prj/create_project.tcl` 可移植重建入口。
- Changelog、贡献指南、安全策略和 v1.0.0 发布 Checklist 已建立。
- 尚未对当前发布提交执行 Vivado 综合、bitstream 生成或实板验收。

## P0：v1.0.0 发布阻塞项

### 1. 验证 Vivado 工程可重建

责任边界：由发布负责人在安装 Vivado 2024.2 的环境中执行。该步骤启动 Vivado并生成
本地工程元数据，但不启动综合、不生成 bitstream、不访问板卡。

```bash
vivado -mode batch -source prj/create_project.tcl
```

预期产物：

- `prj/YiFPGAStudio.generated/YiFPGAStudio.xpr`
- 本地 Vivado project metadata

完成标准：

- [x] 在全新 clone 或不同绝对路径下成功创建工程。
- [x] 顶层为 `yifpga_debug_board_demo`。
- [x] 器件为 `xcku5p-ffvb676-2-i`。
- [x] RTL、XDC 和 include directory 无缺失或旧机器路径。
- [x] 将 Vivado 日志交回仓库维护者分析，但不提交生成工程目录。

2026-07-20 本机证据：Vivado 2024.2（Build 5239630）先后在仓库工作目录和全新本地
clone `/tmp/YiFPGAStudio-portability-check` 中成功创建 `YiFPGAStudio.xpr`；两次日志均以
`PASS: Created portable YiFPGA Studio project` 正常结束。工程源文件、约束和 include
directory 均以 `$PPRDIR` 相对路径记录，生成目录和 Vivado 日志保持 Git ignored。

### 2. 完成五配置综合门禁

责任边界：用户控制的 Vivado 综合操作。预计耗时取决于主机性能和许可证；不会生成
bitstream，也不会烧录板卡。

```bash
just release-matrix
```

预期产物位于 `prj/YiFPGAStudio.runs/m36_matrix/<configuration>/`：

- `manifest.txt`
- `utilization.rpt`
- `clock_interaction.rpt`
- `cdc.rpt`

完成标准：

- [x] `uart`、`jtag`、`uart_and_jtag`、`jtag_disabled`、`jtag_perf` 全部综合成功。
- [x] BSCANE2 数量与各配置 manifest 一致。
- [x] CDC/clock interaction 报告已人工审查。
- [x] 无不可接受的资源回归。

2026-07-20 Vivado 2024.2 综合证据：五配置均以 `synth_design completed successfully`
结束，矩阵门禁输出 `PASS`，无 `ERROR` 或 `CRITICAL WARNING`。启用 JTAG 的 `jtag`、
`uart_and_jtag`、`jtag_perf` 各含 1 个 BSCANE2，禁用 JTAG 的 `uart`、
`jtag_disabled` 均为 0。五份 CDC 报告均为 `All paths are Safely Timed`；clock
interaction 均为单一 `sys_clk_p` 自时钟、`Clean`/`Timed`、TNS 0，综合 WNS 为
+6.12 ns 至 +6.45 ns。顶层资源范围为 3,149–5,027 LUT、3,370–5,621 FF、0–1
RAMB36、0 DSP；配置间变化与 UART/JTAG/perf 功能开关一致。

### 3. 生成并审查发布镜像

责任边界：用户控制的长时间 Vivado 综合、实现、布局布线和 bitstream 生成操作；不会
自动烧录板卡。

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

完成标准：

- [x] WNS 非负且不存在未布线网络。
- [x] DRC、CDC、时序和资源报告已人工审查。
- [x] BSCANE2 和 ILA 数量均为 1。
- [x] 记录 bitstream、LTX 和源码提交的 SHA-256/commit 对应关系。

2026-07-20 Vivado 2024.2 发布镜像证据：实现后 WNS +2.907 ns、TNS 0、WHS
+0.013 ns，11,374 条可布线网络全部完成且 routing error 为 0；BSCANE2 和 ILA 均为
1。DRC 的 3 个 `PDCN-1569`、1 个 `RTSTAT-10` 以及 CDC 的 4 个 `CDC-15` warning
均位于 Vivado 生成的 `dbg_hub` 内部，未发现用户 RTL 的 DRC/CDC 问题。顶层实现资源为
6,065 LUT、7,364 FF、3 RAMB36、0 DSP。构建源码提交为
`266e9dd0209f42ed4e47f50bd5ac7cc381f972a9`，且构建时 RTL、XDC、bitstream Tcl 和
justfile 相对该提交无修改：

- bitstream SHA-256：`e38a637c191bdadb9b209ea4423ab7dca0c7ff93864cd7396775da2fb1790787`
- LTX SHA-256：`019c53da47cee5fb7cecfc429efe703e9b07c038e9534a906d47e44cca115622`

### 4. 完成实板验收与长稳测试

责任边界：以下操作访问真实 JTAG cable 和 FPGA。烧录命令会改写目标 FPGA 当前配置，
必须由发布负责人确认唯一的精确 target 后执行。

```bash
just release-program <exact-target>
```

若只连接了一个 JTAG target，可省略 target 选择并让脚本在“恰好一个 target、恰好一个
FPGA”的条件下自动下载：

```bash
just release-program-auto
```

烧录后启动 normal 模式的 FTDI Bridge：

```bash
just release-bridge
```

另开终端验证 normal JTAG 数据和一次客户端重连，并使用实际串口路径验证 UART
`115200 8N1`：

```bash
just release-jtag-smoke
just release-uart-validate <serial-device> 30 50 prj/YiFPGAStudio.runs/release/uart_capture.bin
```

normal 镜像用于 UART/JTAG/Viewer 功能验证和低速长稳验证。其业务数据生成速率不用于
100,000 B/s 性能门禁。性能门禁必须构建并下载 `jtag_perf` 专用连续数据源镜像：

```bash
just release-perf-bitstream
just release-perf-program-auto
just release-perf-bridge
```

在另一终端运行 30 分钟性能 soak：

```bash
just release-soak 1800 3 prj/YiFPGAStudio.runs/m36/m36_perf_soak.csv
```

完成标准：

- [x] 烧录时只匹配一个 target 和一个 FPGA，且枚举一个 ILA。
- [x] UART `115200 8N1` 和 JTAG Bridge 基本功能通过。
- [x] Web Viewer 七类视图和 AI Debug 基本流程通过。
- [x] 平均吞吐不低于 100,000 B/s。
- [x] drop/overflow 计数在测试窗口内不增长。
- [x] 三次客户端重连成功，`last_error` 为空。
- [x] 保存 soak CSV、Bridge 日志、板卡/线缆标识和异常说明。

2026-07-20 自动唯一目标下载证据：`just release-program-auto`（当时兼容命令名为
`m36-program-auto`）唯一选择
`localhost:3121/xilinx_tcf/Digilent/210512180081`，唯一器件为 `xcku5p_0`；下载完成后
Vivado 识别 1 个 ILA 并输出 `PASS: Programmed M36 JTAG+ILA image`。

2026-07-20 normal 镜像 1,800.022 秒 soak 证据：完成 3 次客户端重连，4 个 HELLO，
`last_error` 为空，drop/overflow 首尾均为 150,815、窗口内未增长，slow client 为 0。
平均 884.025 B/s 符合 normal 低速业务源特征，但不满足性能门禁；性能项改由
`m36_perf_ila` 连续数据源复验。

2026-07-20 performance 镜像 1,800.007 秒 soak 证据：传输 277,550,080 bytes，平均
154,193.906 B/s，p50/p99 数据间隔为 6.753/9.074 ms；完成 3 次客户端重连和 4 个
HELLO，drop/overflow 首尾均为 0，`last_error` 为空，slow client 为 0。性能镜像实现 WNS
+3.770 ns、TNS 0，8,350 条可布线网络全部完成。performance bitstream SHA-256 为
`9e2f2a6907acd55c5cf8a585c0016cfdfa9a7d3f5bb88ab0094d86e0851791ce`，LTX SHA-256 为
`019c53da47cee5fb7cecfc429efe703e9b07c038e9534a906d47e44cca115622`。

2026-07-20 normal JTAG 冒烟证据：60.050 秒接收 53,103 bytes，平均 884.311 B/s，
完成 1 次客户端重连和 2 个 HELLO；drop/overflow 首尾均为 24,765、窗口内未增长，
`last_error` 为空，slow client 为 0。CSV 保存于
`prj/YiFPGAStudio.runs/release/jtag_smoke.csv`。

2026-07-20 首次 UART 冒烟未通过：板内 status drop count 首尾均为 0，但主机检测到 1
个 checksum error；坏帧 `a501030b81969800011001020000019f` 的期望 XOR checksum 为
`0x95`。需用 30 秒原始采集复测，发布门禁继续保持未完成。

2026-07-20 UART 严格复测通过：30.000 秒接收 26,529 bytes、1,678 个有效帧，覆盖
DEBUG_PRINT、EVENT、HEARTBEAT、STATUS、TRACE 和 WATCH 等 9 类消息；checksum/version
error 均为 0，status drop count 全程为 0。原始 capture SHA-256 为
`75a94a6d391bd84f1670492de6b36389f3292b8d6ec9468a159660841938aade`。

2026-07-20 实板 Web Viewer 人工验收通过：Log、Watch、Events/Status、Trace、Monitor、
Profiler、Logic Analyzer 均正常；Logic Analyzer 完成配置、Arm、Force、Readout 和波形
检查；AI Debug 的 current session/latest LA capture、本地分析、完整 evidence preview、Mock
Provider 和 evidence 回链流程通过。

2026-07-20 Monitor 安全写验收通过：`LED_CONTROL` 从原值 `0x00000000` 临时写为
`0x00000003` 后成功恢复；只读寄存器写入返回状态 2，非法地址返回状态 1。

2026-07-20 Bridge 证据归档：normal Bridge 以 FTDI、6 MHz TCK、1,024-byte block 和
Build ID `0x4d360001` 启动；随后 60.017 秒接收 53,122 bytes，完成 1 次客户端重连，
drop/overflow 首尾均为 64,626、窗口内未增长，`last_error` 为空。Bridge log SHA-256 为
`20cc9348535d09ae6dcca45e4540dadc057851473036c2be9d5ca894b67dd4e2`，对应 smoke CSV
SHA-256 为 `dbbd8646f5d14bdfab090127c5cb306d3f37a66c6441c9f4ed9c0664c0f04194`。

实板标识为 `ATK-KU5`；JTAG cable target 为
`localhost:3121/xilinx_tcf/Digilent/210512180081`；UART 设备为
`/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`。已知异常仅为首次 UART 5 秒冒烟出现
1 个 checksum error，随后 30 秒严格复测为 0 error，原始 capture 已留存。

### 5. 发布 v1.0.0

前置条件：P0 的工程、综合、镜像和实板验收全部通过。

完成标准：

- [x] 将 `CHANGELOG.md` 的 `Unreleased` 转为 `1.0.0` 并填写发布日期。
- [x] README 去掉“候选”表述，写明最终验证的 Vivado、器件和板卡。
- [ ] 所有发布证据可追溯到同一源码提交。
- [ ] 创建并推送 annotated tag `v1.0.0`。
- [ ] 创建 GitHub Release，列出平台边界和已知限制。
- [ ] 若提供 bitstream，同时提供匹配的 LTX、目标说明和 SHA-256；产物不提交进 Git。

## P1：发布工程改进

### 6. 消除 GitHub Actions Node 20 弃用警告

当前门禁通过，但 GitHub runner 提示部分 Actions 仍以 Node 20 为目标运行时。升级前应检查
各 Action 的官方 Node 24 兼容版本，并保持权限最小化。

完成标准：

- [x] 更新 `actions/checkout`、`actions/setup-python`、`actions/setup-node` 和 just setup Action。
- [x] 固定到受支持的稳定 major 或审核后的 commit SHA。
- [ ] PR 与 `main` 的 `Release Check` 均通过且不再出现 Node 20 弃用警告。

### 7. 配置 main 分支保护

完成标准：

- [ ] 将 `release-check` 设为合并前 required check。
- [ ] 禁止直接 force-push 和删除 `main`。
- [ ] 根据维护方式决定是否要求 PR review 和线性历史。

### 8. 清理已合并分支

PR #1 已合并，但 `chore/v1-release` 本地和远端分支仍保留。

完成标准：

- [ ] 确认无需继续从该分支取证后删除远端分支。
- [ ] 删除本地分支并执行 `git fetch --prune`。

## P2：v1.0.0 之后

- [ ] 评估 Qt Viewer 的范围、依赖和维护成本。
- [ ] 为 Intel、Lattice 和国产 FPGA 制定 vendor abstraction 与验证矩阵。
- [ ] 评估 PCIe、Ethernet、USB、SPI Transport 的协议复用和安全边界。
- [ ] 建立可重复的性能基线、资源趋势和跨版本回归记录。
- [ ] 根据首个正式版本反馈确定 v1.0.1 或 v1.1.0 路线图。

## 推荐执行顺序

```text
可移植工程重建
  → 五配置综合
  → normal+ILA 实现与镜像
  → 精确目标烧录
  → UART/JTAG/Viewer 冒烟
  → 30 分钟 soak
  → 发布材料更新
  → v1.0.0 tag 与 GitHub Release
```
