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

- [ ] 在全新 clone 或不同绝对路径下成功创建工程。
- [ ] 顶层为 `yifpga_debug_board_demo`。
- [ ] 器件为 `xcku5p-ffvb676-2-i`。
- [ ] RTL、XDC 和 include directory 无缺失或旧机器路径。
- [ ] 将 Vivado 日志交回仓库维护者分析，但不提交生成工程目录。

### 2. 完成五配置综合门禁

责任边界：用户控制的 Vivado 综合操作。预计耗时取决于主机性能和许可证；不会生成
bitstream，也不会烧录板卡。

```bash
just m36-matrix
```

预期产物位于 `prj/YiFPGAStudio.runs/m36_matrix/<configuration>/`：

- `manifest.txt`
- `utilization.rpt`
- `clock_interaction.rpt`
- `cdc.rpt`

完成标准：

- [ ] `uart`、`jtag`、`uart_and_jtag`、`jtag_disabled`、`jtag_perf` 全部综合成功。
- [ ] BSCANE2 数量与各配置 manifest 一致。
- [ ] CDC/clock interaction 报告已人工审查。
- [ ] 无不可接受的资源回归。

### 3. 生成并审查发布镜像

责任边界：用户控制的长时间 Vivado 综合、实现、布局布线和 bitstream 生成操作；不会
自动烧录板卡。

```bash
just m36-ila-bitstream
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

- [ ] WNS 非负且不存在未布线网络。
- [ ] DRC、CDC、时序和资源报告已人工审查。
- [ ] BSCANE2 和 ILA 数量均为 1。
- [ ] 记录 bitstream、LTX 和源码提交的 SHA-256/commit 对应关系。

### 4. 完成实板验收与长稳测试

责任边界：以下操作访问真实 JTAG cable 和 FPGA。烧录命令会改写目标 FPGA 当前配置，
必须由发布负责人确认唯一的精确 target 后执行。

```bash
just m36-program <exact-target>
```

烧录后启动 normal 模式的 FTDI Bridge：

```bash
just m36-ftdi-bridge
```

在另一终端运行 30 分钟 soak：

```bash
just m36-soak 1800 3 prj/YiFPGAStudio.runs/m36/m36_soak.csv
```

完成标准：

- [ ] 烧录时只匹配一个 target 和一个 FPGA，且枚举一个 ILA。
- [ ] UART `115200 8N1` 和 JTAG Bridge 基本功能通过。
- [ ] Web Viewer 七类视图和 AI Debug 基本流程通过。
- [ ] 平均吞吐不低于 100,000 B/s。
- [ ] drop/overflow 计数在测试窗口内不增长。
- [ ] 三次客户端重连成功，`last_error` 为空。
- [ ] 保存 soak CSV、Bridge 日志、板卡/线缆标识和异常说明。

### 5. 发布 v1.0.0

前置条件：P0 的工程、综合、镜像和实板验收全部通过。

完成标准：

- [ ] 将 `CHANGELOG.md` 的 `Unreleased` 转为 `1.0.0` 并填写发布日期。
- [ ] README 去掉“候选”表述，写明最终验证的 Vivado、器件和板卡。
- [ ] 所有发布证据可追溯到同一源码提交。
- [ ] 创建并推送 annotated tag `v1.0.0`。
- [ ] 创建 GitHub Release，列出平台边界和已知限制。
- [ ] 若提供 bitstream，同时提供匹配的 LTX、目标说明和 SHA-256；产物不提交进 Git。

## P1：发布工程改进

### 6. 消除 GitHub Actions Node 20 弃用警告

当前门禁通过，但 GitHub runner 提示部分 Actions 仍以 Node 20 为目标运行时。升级前应检查
各 Action 的官方 Node 24 兼容版本，并保持权限最小化。

完成标准：

- [ ] 更新 `actions/checkout`、`actions/setup-python`、`actions/setup-node` 和 just setup Action。
- [ ] 固定到受支持的稳定 major 或审核后的 commit SHA。
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
