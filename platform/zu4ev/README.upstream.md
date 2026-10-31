# Zynq ZU4EV SC130GS Camera Platform

当前基线是 **2026-10-26 已部署到 QSPI 的 AE RAW10 亮度统计版本**。
这是自动曝光算法的前置测量模块，尚不是新增的软件自动曝光闭环。
实板结果及验证边界见 [AE 部署记录](reports/ae_stats/board/RESULTS.md)。
当前源码、匹配启动材料和本地部署产物围绕这一版本保留；历史构建目录不作为依赖。

SC130GS 1280×1024 RAW10 → ISP 黑位校正、Tone Mapping/LTM、TNR → 双 VDMA → Linux → DP / USB 3.0 UVC YUY2。
顶层为 `rtl/camera_top.v`，结构见 [RTL 层级](rtl/README.md)，算法见 [ISP 说明](isp/README.md)。
AE 提供四档中心区域、黑位扣除、总和/像素数/均值与错误计数。
板上可用 `ispctl stats status`、`ispctl stats read` 查看数据；`ispctl stats set region 0/1/2/3` 分别选择中心面积 1/4、1/2、3/4、全屏。

## 构建入口

使用 Vivado/Vitis **2025.1**，器件 `xczu4ev-sfvc784-2-i`，顶层 `camera_top`，定义 `SC130_UVC`；CSI-2 RX 需要本机有效 IP 许可。

```powershell
vivado -mode batch -source tools/recreate_project.tcl
vivado -mode batch -source tools/build_platform.tcl
```

首次重建生成 `vivado/camera/camera.xpr`，后续直接使用构建入口。
`hardware/*.tcl` 保存 PS、CSI、时钟、ILA 与 DDR 配置，不依赖相邻旧工程。
生成物为 `build/ae_stats/artifacts/camera_ae.bit`、`.ltx`、`.xsa`；综合/布线检查点为 `build/ae_stats/camera_top_synth.dcp` 与 `camera_top_routed.dcp`。
每次构建报告单独写入 `reports/ae_stats/builds/<时间戳>-<进程号>/`，已有实板报告仅记录其当时版本，不能当作新构建验证结果。

```powershell
# 仅生成 BOOT.BIN；不连接板卡或烧写
powershell -File tools/package_ae.ps1
# 临时 RAM 启动专用 BOOT.BIN，不能用作正式 QSPI 启动文件
powershell -File tools/package_ae.ps1 -RamTest
```

默认输出分别为 `build/ae_stats/qspi` 和 `build/ae_stats/ram`。
`boot/prebuilt/` 是与当前 PS 配置匹配的已验证 FSBL/PMUFW/ATF/U-Boot 二进制种子；PS 配置变化后必须重新生成匹配固件与 BSP。
`firmware/boot_reference/` 保留生成的 FSBL/PMU 源码和 BSP 参考，定制构建见 [FSBL 说明](boot/fsbl/README.md)。

在具备 `mkimage`、`dumpimage`、`fdtget` 的 Linux/WSL 环境执行 `python3 tools/package_isp_control_linux.py`，默认从 `firmware/linux/` 读取内核、设备树和 initramfs 种子，把 `build/ae_stats/software/` 中的 `ispctl`、`sensorctl` 放入 FIT，输出到 `build/ae_stats/qspi/`。
这一步是重打包，不是完整 Linux 重编译。完整构建仍依赖外部 WSL 内核/根文件系统树和交叉工具链，见 [构建依赖](docs/BUILD_DEPENDENCIES.md) 与 [Linux 说明](linux/README.md)。
`tools/create_full_ae_project.tcl`、`tools/package_full_ae_project.py` 保留为便携工程生成工具。

## 使用与证据

Mini DP 接显示器，电脑接板上 USB1（芯片 PS USB0）；USB 数据线须支持 SuperSpeed。
主机选择 UVC Camera、YUY2、1280×1024、120 fps。摄像头持续采集，主机开关 USB 流不停止 DP。
正式 QSPI 启动包含 FSBL、PMUFW、PL、ATF、生产 U-Boot 和 Linux FIT；32 MiB Flash 中 BOOT 从 0 开始，FIT 从 `0x00c00000` 开始。

已部署版本完成 QSPI 读回、复位启动和独立 Linux 重启验证，30 秒 USB 实采约 119.89 fps，AE/DDR 错误未增加；未执行断电再上电测试。
此前一直存在的 USB 缓冲错误按用户要求暂时忽略，尚未修复，不能宣称全链路零错误。
传感器曝光调节的稳定亮度响应已测；精确 N+2 生效帧仍是资料结论，未完成逐帧实测。

源码回归保留在 `sim/`、`software/`、`linux/tests/` 与启动打包测试中。
`sim/ae_stats/` 保存当前统计模块回归及实板工具；实板视频脚本使用 `tools/host-deps/ffmpeg.exe`。
本地生成固件、工具缓存、Flash 备份和实拍数据不属于源码发布；镜像身份应以对应产物清单和哈希为准。
