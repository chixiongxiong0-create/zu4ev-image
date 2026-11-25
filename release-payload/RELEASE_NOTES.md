2026-11-25 ZU4EV 定版发布，Vivado 2025.1，XCZU4EV-SFVC784-2-I。

- 集成无需标定的在线动态 DPC，保留静态 DPC、FFC、AE、BLC/LTM、TNR 和 NV12/VCU 链路。动态 DPC 复位默认旁路，可配置观察和修复模式。
- ENABLE_CAMERA_ILA 和 ENABLE_UVC_ILA 两个独立开关默认关闭，GPIO 状态、快照和 AE 事件保留。
- 已布线 BRAM 84/128；WNS +0.038 ns，WHS +0.010 ns；DRC 错误和路由错误均为 0。
- 动态 DPC 1280×1024、11 帧、7,209,600 个像素对回归通过；静态 DPC、窗口和实际前端 AXI 回归通过。

发布源码提交为 83ba2627fa73e4b6b8f0a58f88e10e751f42161b，通过 GitHub MCP 提交。其完整源码树与本地冻结提交 b84b697027ea0b1cf814fbfe643c63e0b0a81b4d 一致，树 SHA 为 050cbaf829feb11f8b8a889a7c8fde2608180490。原始构建 manifest 保留本地冻结提交编号。

硬件 ZIP 包含当前 camera_top.bit、camera_top.ltx、原始构建 manifest、工程重建脚本、源 IP、输入 ROM/系数/约束、实现报告和回归记录。按原有 build/dpc 目录解压到匹配的源码检出中。ZIP 内外均提供 SHA-256 校验。未包含体积较大的 routed DCP、生成缓存、BOOT.BIN 或 QSPI 镜像。

物理实现完成于 2026-11-11，当前 bitstream 于 2026-11-25 从该布线检查点生成。依赖路径迁移前后输入内容一致，迁移后未重新综合布线。VCU 时钟方法学严重警告和一组 bus-skew 忽略警告仍在，时序余量较窄。本次 bitstream 尚待上板验证。

详情见 [定版记录](https://github.com/chixiongxiong0-create/zu4ev-image/blob/83ba2627fa73e4b6b8f0a58f88e10e751f42161b/docs/verification/2026-11-25-zu4ev-final.md)。