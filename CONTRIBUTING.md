# 参与贡献

感谢参与 YiFPGA Studio。提交改动前，请先确认改动范围清晰，并避免把本地生成物、
板卡凭据或硬件采集数据加入仓库。

## 开发流程

1. 从最新的 `main` 创建主题分支。
2. 将功能、重构和文档改动拆成范围明确的提交。
3. 运行与改动相关的快速测试。
4. 提交 pull request，说明目的、验证方法和已知限制。

提交信息建议采用 `type: summary` 格式，例如：

```text
feat: add trace filter
fix: preserve packet order on overflow
docs: clarify monitor register access
```

## 无硬件发布检查

提交 pull request 前运行：

```bash
just release-check
```

该命令执行协议解析、Web Viewer、AI Debug 和 JTAG Bridge 的离线回归，不调用
Vivado，不生成 bitstream，也不访问真实板卡。

如果只修改某个子系统，可以先从 `just --list` 选择对应的快速检查，再执行完整的
`release-check`。

## RTL 与 FPGA 验证

RTL 改动应说明：

- 受影响的模块、时钟域和复位行为；
- 新增或更新的 testbench；
- 综合、时序、CDC 或 DRC 风险；
- 使用的器件、Vivado 版本和验证命令。

Vivado elaboration、综合、实现、bitstream 生成和板卡烧录不属于自动 CI。执行这些操作
前应检查目标器件、约束、输出目录和 cable target，并在 pull request 中附上相关报告摘要。

不要提交 `.bit`、`.dcp`、`.ltx`、Vivado run 目录、硬件抓取文件或包含机器绝对路径的
临时工程状态。

## Pull request 检查项

- [ ] 改动与 pull request 描述一致。
- [ ] `just release-check` 通过，或已解释无法运行的原因。
- [ ] 新行为包含相应测试或验证记录。
- [ ] 文档和 Changelog 已按需更新。
- [ ] 未提交生成物、密钥、串口标识或不必要的板卡数据。

