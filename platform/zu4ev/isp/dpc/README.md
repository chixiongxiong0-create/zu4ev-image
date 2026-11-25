# Mono RAW10 坏点校正

DPC 按已确认的坐标修复。表外像素在 DPC 输入和输出之间逐位相同，真实的单像素亮点不会因亮度被删除。模块位于 FFC 后、AE 统计及 BLC/LTM 前，每时钟处理两个像素。

坏点表最多 1024 个水平连续段，每段 1～32 个像素。段两端使用表外原始邻点做四舍五入的线性插值；图像边缘使用可用的一侧。二维坏点簇按行修复。超过 32 像素的水平连续段、整行坏点和超出表容量的情况会被拒绝，不能拆成相邻短段绕过限制。坐标绑定 sensor、裁切、翻转和采样模式；更换这些条件后要重新确认坐标。

寄存器、数据路径与测试范围见 [DESIGN.md](DESIGN.md)。复位默认旁路。上表前应在遮黑或均匀亮场下确认候选点，避免把场景像素写进表。

```sh
ibex_isp_handoff stop
dpcctl status
# 完全遮黑，固定曝光/增益。阈值需高于本机暗场和噪声底。
dpcctl survey /tmp/dark.survey raw high 80 64
```

将 `dark.survey` 取回主机后生成坐标表。默认要求候选点在至少 95% 的采样帧持续出现。采集溢出或坏帧时整批拒绝。

```powershell
python platform/zu4ev/isp/dpc/make_map.py --survey dark.survey --output dark.dpc --report dark-dpc.json
# 两批同条件调查，取两批都持续出现的坐标。
python platform/zu4ev/isp/dpc/make_map.py --survey dark-a.survey --survey dark-b.survey --require-all-surveys --output confirmed.dpc --report confirmed.json
# 已确认坐标也可从文本导入，每行 x y（零起点）。
python platform/zu4ev/isp/dpc/make_map.py --coordinates defects.txt --output defects.dpc --report defects.json
```

复制地图到板端后：

```sh
dpcctl load /tmp/dark.dpc
dpcctl status
dpcctl survey /tmp/after.survey corrected high 80 64
# 恢复 AE 前先退出所有 PS 控制程序。
ibex_isp_handoff start --ps-writers-stopped
```

`load` 在访问硬件前验证完整文件，向非活动 bank 顺序写入并逐项读回，再在输出 SOF 应用；`disable` 也在输出 SOF 生效。工具共享现有 ISP 与 ownership 锁。RAM 标定启动镜像通过 `/tmp/ffc-allow-ae` 恢复协调器，使用该镜像时应创建标志，而非同时手动运行 handoff。

冷坏点需要在均匀、未饱和的亮场下使用 `raw low` 采集，或从已确认坐标导入。A53 只负责显式标定和一次性配置，视频校正由 PL 实时完成。

```powershell
powershell -File tests/zu4ev/dpc/run.ps1 -Full
powershell -File tests/zu4ev/dpc/run_axi.ps1
python tests/zu4ev/dpc/test_make_map.py
```
