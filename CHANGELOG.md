# Changelog

YiFPGA Studio 的重要变更记录在此文件中。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循
[Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- 为 pull request 和 `main` 分支添加无硬件、无网络的自动发布检查。
- Debug Protocol v1，以及 Debug Core、时间戳、ring buffer 和 UART 收发链路。
- Trace、Monitor、Profiler 和 Logic Analyzer RTL、协议扩展与 Web Viewer 视图。
- UART 和 Xilinx BSCAN/USER2 JTAG Transport，以及本地 JTAG Bridge。
- 基于诊断快照、本地规则和受校验 Provider 边界的 AI Debug。
- 面向 `xcku5p-ffvb676-2-i` 的参考板级 Demo、约束和 Vivado 脚本。
- 协议解析、Viewer、AI Debug 和 JTAG Transport 的无硬件回归测试。

### Known limitations

- 1.0.0 系列仅承诺 Xilinx `xcku5p-ffvb676-2-i` 参考实现。
- Qt Viewer、其他 FPGA 厂商以及 PCIe/Ethernet/USB/SPI Transport 尚未纳入本版本。
- 正式 `v1.0.0` 发布仍需完成可复现 Vivado 构建与实板发布门禁。

[Unreleased]: https://github.com/Don-207/YiFPGAStudio/commits/main
