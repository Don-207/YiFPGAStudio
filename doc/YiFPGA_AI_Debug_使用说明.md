# YiFPGA Studio AI Debug 使用说明

AI Debug 将当前 Viewer 会话整理为不可变诊断快照，先运行本地确定性规则，再由用户选择是否把脱敏、裁剪后的上下文交给 Provider。AI 结论不会覆盖本地 finding，也不会自动执行建议。

## 快速开始

1. 连接硬件、回放 raw capture，或点击 `Inject Sample`。
2. 在 `AI Debug` 区域选择当前会话、时间窗或最新 LA capture。
3. 点击 `Run Local Analysis`，检查 Evidence Preview、完整性和本地 Findings。
4. 点击 evidence ID 可返回 Trace、Profiler、Monitor、Logic Analyzer、Transport 或 Log 区域。
5. 如需 Mock AI 分析，先阅读 Provider preview，再勾选确认并点击 `Ask Mock AI`。
6. 可取消运行中的请求；本地 finding 在 Provider 失败、超时或取消后仍然保留。

## 结果语义

- Local Findings 是版本化规则基于输入 evidence 得出的确定性事实。
- AI Hypotheses 仅显示通过 schema、置信度和 evidence 白名单校验的结果。
- 跨来源时间重叠不代表因果关系；需要通过建议的只读检查人工验证。
- `unverified`、低置信度或 conflict 标记表示证据不足或与本地规则存在冲突。

## 隐私与授权

Provider 上下文会先移除凭据、路径、串口设备名、工程名和备注等敏感字段，再计算预算和序列化。Evidence Preview 显示发送数量、裁剪数量、估算大小和脱敏字段数，不显示凭据。未勾选显式确认时不会请求 Provider。

当前页面默认使用无网络的 Mock Provider。真实 Provider 适配器只保存凭据引用；凭据值不得进入 snapshot、历史、错误或导出文件。

## 导出与限制

- Snapshot JSON：M27 原始证据包。
- Diagnosis JSON：引用 snapshot ID 的本地 finding、已校验 AI 结果和本地 feedback。
- Markdown：适合人工复盘的摘要报告。

History 和 Feedback 仅保存在当前页面会话中。`Clear` 会清除 Viewer 数据和 AI Debug 会话。AI Debug 不会写 Monitor、控制 LA、下载 bitstream、运行构建或修改工程文件。
