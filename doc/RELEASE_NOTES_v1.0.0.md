# YiFPGA Studio v1.0.0

YiFPGA Studio v1.0.0 是首个独立正式版本，提供统一 Debug Protocol、Debug Core、Trace、
Monitor、Profiler、Logic Analyzer、AI Debug、UART/JTAG Transport 和 Web Viewer。

## 已验证参考平台

- 板卡：ATK-KU5
- FPGA：Xilinx `xcku5p-ffvb676-2-i`
- Vivado：2024.2 Build 5239630
- UART：115200 8N1
- JTAG：Digilent cable，BSCAN USER2
- Host：Ubuntu 22.04.5 LTS、Python 3.10.12、Node.js v20.20.2、just 1.56.0

## 发布验收摘要

- 在两个不同绝对路径成功重建 Vivado 工程，无旧机器源文件路径。
- `uart`、`jtag`、`uart_and_jtag`、`jtag_disabled`、`jtag_perf` 五配置综合通过。
- normal+ILA 镜像实现 WNS +2.907 ns，无未布线网络，BSCANE2/ILA 均为 1。
- performance+ILA 镜像实现 WNS +3.770 ns，无未布线网络。
- UART 30 秒严格验证收到 1,678 个有效帧，checksum/version error 和 drop count 均为 0。
- normal JTAG 完成 30 分钟稳定性和客户端重连验证，验证窗口内 drop/overflow 未增长。
- performance JTAG 30 分钟传输 277,550,080 bytes，平均 154,193.906 B/s，drop/overflow 为 0。
- Web Viewer 七类视图、Logic Analyzer 实板采集和 AI Debug 本地/Mock Provider 流程通过。
- Monitor 可恢复写、只读保护和非法地址错误响应通过。

## 发布镜像校验

normal+ILA：

- bitstream SHA-256：`e38a637c191bdadb9b209ea4423ab7dca0c7ff93864cd7396775da2fb1790787`
- LTX SHA-256：`019c53da47cee5fb7cecfc429efe703e9b07c038e9534a906d47e44cca115622`

performance+ILA：

- bitstream SHA-256：`9e2f2a6907acd55c5cf8a585c0016cfdfa9a7d3f5bb88ab0094d86e0851791ce`
- LTX SHA-256：`019c53da47cee5fb7cecfc429efe703e9b07c038e9534a906d47e44cca115622`

如分发 bitstream，必须同时提供匹配的 LTX、目标器件/板卡说明和上述 SHA-256。生成物不
提交进 Git。

## 已知限制

- 1.0.x 仅承诺上述 Xilinx/ATK-KU5 参考平台；其他器件和板卡需要独立验证。
- Intel、Lattice 和国产 FPGA 尚无 vendor abstraction 与发布验证矩阵。
- PCIe、Ethernet、USB、SPI Transport 和 Qt Viewer 不属于本版本。
- Web Viewer 需要 Chrome 或 Edge；Web Serial 的可用性受浏览器安全策略影响。
- JTAG performance 镜像使用专用连续数据源，不代表 normal 业务帧的生成速率。
- JTAG/Monitor 接口面向可信开发与调试环境，不应直接作为生产访问控制边界。
