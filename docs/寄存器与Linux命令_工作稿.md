# ZU4EV 寄存器与 Linux 命令（工作稿）

更新日期：2026-11-06。依据当前 `E:/workspace/AI_Projects/RISC_V/ibex/platform/zu4ev` 与 `integration/small` 源码，面向最终 ISP/TNR 后分叉的 YUY2 显示 + PL NV12/VCU H.264 版本。sensor 统称图像传感器；源码历史标识和设备节点保留原名。

NV12 已完成 RAM 上板和 USB 接收/解码，未更新 QSPI；本次文档更新不表示重新上板或冷启动验收。本文维护入口为当前工程 `docs/寄存器与Linux命令_工作稿.md`，旧工程目录中的同名文件保留同步副本。所有寄存器为 32 位小端字，表中偏移相对基址；不要访问未映射地址。驱动管理的 DMA/缓冲寄存器不得在运行中用 devmem 改写。

## 当前地址总览

| A53 物理基址 | 对象 |
|---|---|
| 0xA0000000 / 0xA0020000 | YUY2 双路 AXI VDMA |
| 0xA0010000 / 0xA0030000 | 双相位 capture |
| 0xA0040000 | ISP、RAW AE 统计及 PS/Ibex 所有权窗口 |
| 0xA0050000 | TNR |
| 0xA0060000 / 0xA0070000 | RAW 调试 VDMA / capture |
| 0xA0080000 | NV12 输出外设，64 KiB，ABI v2 |
| 0xA1000000 | VCU 控制区域基址，实际子设备由设备树和驱动管理 |

Ibex 视角：snapshot=0x50000000、ISP 配置=0x51000000、sensor 控制=0x52000000、AE mailbox=0x0023e000。这些不是 A53 /dev/mem 地址。

## ISP 与 AE：基址 0xA0040000

| 偏移 | 权限 | 说明 |
|---|---|---|
| 0x000 | R | ISP ID 0x49535031 |
| 0x004 | R | 版本 0x00010000 |
| 0x008 | R | 能力：bit0 参数、bit1 双曲线、bit2 sigma、bit3 状态、bit4 RAW 统计、bit5 AE 开关、bit6 BLC 开关、bit7 tone 开关 |
| 0x00c | R | bit0 参数提交等待、bit1 当前曲线 bank、bit2 帧处理忙 |
| 0x010 | RW | 影子模式：0 LTM、1 全局曲线、2 原始线性（跳过 BLC）、3 恒等基础层加细节 |
| 0x014 | RW | 影子 BLC 值，0..1022，默认 52 |
| 0x018 | RW | 影子细节增益 Q8，0..512，默认 256 |
| 0x01c | RW | 影子 sigma 编码：0=64、1=32、2=128 |
| 0x020 | W | 1 提交影子参数；3 提交并切换曲线 bank；读为 0 |
| 0x024 | R | 已生效提交序号 |
| 0x028 | R | 完整输出帧数 |
| 0x02c | R | 输入故障数 |
| 0x030 | R | 输入 FIFO 占用 |
| 0x034/038/03c/040 | R | 活动模式、有效黑电平、细节增益、sigma 编码 |
| 0x048/04c | R | 宽和高 |
| 0x050 | R | 滤波窗口 0x00050005 |
| 0x058 | R | 曲线长度 1024 |
| 0x05c/060 | RW/R | BLC 影子/活动开关，0 关闭、1 开启；提交生效 |
| 0x064/068 | RW/R | tone 影子/活动开关，0 关闭、1 开启；提交生效 |
| 0x200 | R | RAW 统计 ID 0x41455331 |
| 0x204 | R | RAW 统计版本 0x00010000 |
| 0x208 | RW | 统计 bit0 使能、bits2:1 区域；默认 7，下一 RAW SOF 生效 |
| 0x20c | RW | 统计独立黑电平 0..1023，默认 52；下一 RAW SOF 生效 |
| 0x210 | R | bit0 有效、bit1 除法忙、bit2 当前帧使能 |
| 0x214/218/21c/220 | R | 结果序号、输入帧号、均值、像素数 |
| 0x224/228 | R | 累加和低 32 位、高 16 位 |
| 0x22c/230 | R | 坏帧数、统计计算溢出数 |
| 0x234 | R | 结果区域 bits1:0、黑电平 bits17:8 |
| 0x238/23c/240/244 | R | 结果 ROI 的 x、y、宽、高 |
| 0x248 | RW | 历史 AE control enable，0/1；仍由 RTL 保留，不能代替 Ibex RUN/STOP 和所有权交接 |
| 0x1000..1ffc | RW | 非活动曲线 bank，1024 个字，每字低 10 位 |

BLC 和 tone 是影子配置，写入后要 `ispctl apply`。关闭 BLC 将有效
黑电平设为零，但保留影子值；RAW 统计黑电平独立。关闭 tone 输出经
BLC 后的原始灰度，但内部空间处理流水线仍存在。当前 AE 主控为 Ibex。停止必须通过 ibex_isp_handoff stop，等待固件/I2C 静止并收回所有权；不能将历史 AE enable 当作安全停机屏障。旧硬件必须先检查能力位，
不得直接访问新增偏移。

## TNR：基址 0xA0050000

| 偏移 | 权限 | 说明 |
|---|---|---|
| 0x00/04/08 | R | ID 0x544e5231、版本 0x00010000、能力 0x0f |
| 0x0c | R | bit0 等待提交、1 DDR 已校准、2 历史有效、3 处理忙、4 自检忙、5 自检完成 |
| 0x10/14/18/1c | RW | 影子使能、alpha 0..256、运动低阈 0..254、高阈 1..255 |
| 0x20 | W | 1 提交、2 清历史、3 提交并清历史、4 内存自检 |
| 0x24/28/2c/30 | R | 提交序号、帧数、运动像素数、可融合像素数 |
| 0x34/38/3c | R | 流故障、DDR 错误、输入 FIFO 占用 |
| 0x40/44/48/4c | R | 活动使能、alpha、低阈、高阈 |
| 0x50/54/58/5c | R | 内存自检错误数、宽、高、帧字节数 |
| 0x60/64 | R | 两个历史缓冲的 PL DDR 偏移 |

阈值提交要求 low < high；TNR 自检须先旁路并等待 DDR 校准且无提交。
TNR 切换和参数提交等待帧边界；上游曲线或模式变化后应清除历史。

## 预览帧门控：0xA0010000 与 0xA0030000

由 Linux 采集驱动管理，两路寄存器相同；直接操作可能破坏驱动的 DMA
所有权。完整位定义和 epoch/中断握手见 当前源码 `platform/zu4ev/rtl/capture/capture_axi_regs_v2.v`。

| 偏移 | 权限 | 说明 |
|---|---|---|
| 0x00/04 | R | ID 0x55564331、版本 0x00020000 |
| 0x08 | W | bit0 ARM、bit1 abort、bit2 清统计 |
| 0x0c | R | gate 状态 |
| 0x10/14 | RW/R | ARM epoch、结果 epoch |
| 0x18 | R | 结果标志，1 表示成功，其他值表示错误 |
| 0x1c | W | 写入匹配的 epoch 确认结果；必须先停止并排空 DMA |
| 0x20/24/28/2c | R | 输入序号、结果帧号、输出 word 数、行数 |
| 0x30/34/38 | R | 丢弃、溢出、完成计数 |
| 0x3c | RW | 结果中断使能 |
| 0x40/44 | R | 能力/通道、帧相位 |
| 0x48/4c/50 | R | deadline miss、已接受 epoch、目标帧 |
| 0x54/58 | R | source 时钟低/高字；先读低字锁存高字 |
| 0x5c/60 | R | arm 时戳低/高字 |
| 0x64/68 | R | 结果 SOF 时戳低/高字 |
| 0x6c/70 | R | 结果完成时戳低/高字 |
| 0x74/78 | R | 写入 guard 状态、退休字节数 |

AXI VDMA 位于 0xA0000000 和 0xA0020000，由 Linux DMA 驱动管理；
其厂商寄存器定义以 AXI VDMA 产品手册和匹配 XSA 为准，不把它们当
作本工程自定义寄存器。CSI 控制器也有厂商寄存器，由 PL 的 csi_control
独占；FE 状态 0x24 bit31 为 W1C，IER 0x28 bit31，GIE 0x20 bit0。

## RAW10 独立抓帧（可选调试接口）

独立 VDMA 控制基址 `0xA0060000`，RAW 帧门控基址 `0xA0070000`。
门控 ID `0x52415731`，版本 `0x00030000`。其 ARM、epoch、结果、
计数和 guard 寄存器偏移与前述预览门控一致；0x40 为 0x201、0x44 为
1（每帧而非奇偶相位）。0x48 与 0x50 当前固定为零；0x4c 返回接受的
epoch。中断映射为 VDMA SPI 94、门控 SPI 95。门控和 VDMA 均由专用
Linux 驱动管理，运行期间不要通过 `/dev/mem` 直接操作它们。

结果标志：1 成功；2 FIFO 溢出；4 短行；8 长行；16 帧尾有额外数据；
32 提前 SOF；64 中止；128 超时；256 输入故障；512 DMA 错误。0x74
bit0 表示写退休、bit1 表示 guard 错误、bit2 表示总线响应已平衡。
出错后驱动先停复位该独立 VDMA 并确认总线静止，再确认门控结果；
如果不能证明 DMA 静止，缓冲区被隔离直至重启。

每次打开 `/dev/sc130_raw10` 后首次读取触发一帧；仅当门控结果、
DMA 完成及写入退休校验通过后返回数据。格式为 1280×1024 个
小端 16 位字，每字低 10 位为 CSI 接收的原始像素，高 6 位为零，
共 2,621,440 字节；这不是 MIPI 紧密打包的 5 字节/4 像素格式。

## PS/Ibex 交接：ISP 基址 + 0xff00

| 偏移 | 说明 |
|---|---|
| 0xff00 | OWNER，bit0 请求/读取 Ibex 所有权；交接工具负责顺序 |
| 0xff04 | STATUS：bit0 quiescent、bit1 granted、bit2 busy、bit3 armed、bit4 fault、bit6 boot-ready、bit9 stop ack |
| 0xff08 | RUN/停止握手；由工具处理 stop toggle/ack，不建议裸写 |

先停止其他 PS/R5 I2C/ISP 写入者，再执行 start。工具会检查 IIC0 空闲、ISP 待提交和固件状态，不会替你停止其他程序。Ibex 持有 ISP 时，不应运行下面的配置写命令。单独 CPU reset 不等于完整安全交接。

## NV12：基址 0xA0080000

| 偏移 | 权限 | 说明 |
|---|---|---|
| 0x00 / 0x04 | R | ID=0x4e563132，版本=2 |
| 0x08 | RW | CONTROL bit0 IRQ enable、bit1 capture ENABLE，复位为 0 |
| 0x0c | R | bit0 完成帧待取、bit1 池配置就绪、bit2 DMA IDLE |
| 0x10 / 0x14 / 0x18 | RW | 配置槽位 0..3、32 位 DMA base、stride |
| 0x1c | RW | 消费者归还 tag |
| 0x20 | W | 全字写：1 配置、2 TAKE、4 RELEASE、8 STOP |
| 0x24 / 0x28 / 0x2c | R | 待取完成帧 base、stride、tag |
| 0x30 / 0x34 | R | 无缓冲丢帧 / 失败帧计数；主动 STOP 中止帧也可能计失败 |

控制接 M09_AXI，128 bit 写接口接 memory_xbar S06_AXI→HP0 DDR，相关新接口均为 200 MHz。IRQ 接 pl_ps_irq1[0]，GIC INTID136，DT SPI104（<0 104 4>）。

当前四槽 coherent NV12 池共 7.5 MiB；1280×1024、stride1280，每槽 1966080 字节，Y 从 base 开始，UV 从 base+1310720 开始。全部 AXI B 响应退休后才发布完成。`/dev/sc130-nv12` 独占打开，通过 GETBUF 导出 DMA-BUF；DQBUF 获取完成槽，VCU 输入 DQBUF 后才能 QBUF 归还。不是 V4L2 capture 节点，不能当 /dev/video* 使用。

寄存器由 sc130_nv12 驱动管理。STOP 写响应仅表示接受命令；STATUS.IDLE 才表示 PL DMA 排空，而且不表示 VCU 已释放输入。关闭顺序为 STOP/等 IDLE→关闭 VCU→关闭 capture/导出 fd。停止超时需保留仍可能被 DMA 访问的内存，不能强制卸载/重绑来恢复。

## 使用前检查：板端工具版本与 ISP 所有权

板端 `/usr/bin/ispctl` 已确认是旧版本：其 `--help` 不包含 `set blc`、`set tone`，因此执行这些命令会报 `unknown setting`。当前仓库源码支持这些命令，但 NV12 RAM overlay 未同步替换该工具。文档中的新版命令不能直接视为板端现有能力；需部署匹配的新版工具后使用，不能用未经核对的裸寄存器写入绕过检查。

```sh
command -v ispctl
ispctl --help
ibex_isp_handoff status
```

**Ibex 所有权限制同时覆盖 ISP 读取和写入。** 当 `owner=1 run=1 grant=1 armed=1` 时，A53 执行 `ispctl status`、`ispctl stats status` 或裸读 ISP 均可能被 AXI 仲裁器拒绝，并出现 `Bus error`（SIGBUS）。这不是单凭报错就能判定地址变化或硬件损坏。

所有权寄存器窗口仍允许交接工具查询。准备临时调参时，先执行下列流程；每条确认成功后才继续，不要整段盲目粘贴：

```sh
ibex_isp_handoff stop
# 必须成功；应回到 owner=0、run=0、grant=0 且静止
ibex_isp_handoff status
ispctl status
ispctl stats status
```

停止会暂停自动曝光，视频采集与 DP/USB 可继续。若 stop 超时或无法归还所有权，不要继续访问 ISP、强抢总线或复位正在使用的外设。正常归还后仍发生 Bus error 时，才继续检查当前 bitstream、工具默认基址、时钟/复位和映射版本。

配置提交完成、其他 PS/R5 写入者均已停止后，使用 `ibex_isp_handoff start --ps-writers-stopped` 恢复 AE。恢复 Ibex 所有权后，停止直接执行 ISP 查询与写入。该限制不应泛化为所有 TNR/NV12 寄存器均由同一仲裁器保护。

## Linux 终端命令

这些命令要求对应版本的镜像和 root/设备访问权限；除只读查询外会
改变运行状态。`ispctl --help` 和 `tnrctl --help` 显示全部参数。
两者都支持全局选项 `--base PHYS`、`--dev PATH`、`--lock PATH`；
默认地址分别为 0xA0040000 和 0xA0050000，通常无需覆盖。

```sh
ibex_isp_handoff status
ibex_isp_handoff stop          # 等待安全停止并收回 PS 所有权
# 以下 ISP 读写操作均要求 stop 成功、PS 拥有控制权且无其他写入者
ispctl status
# ispctl ae status/enable 是保留的历史控制接口，不用于 Ibex 安全停止
ispctl stats status
ispctl stats read              # mean 为统计均值
ispctl stats set enable 0      # 仅关闭统计，不等同于关闭 AE
ispctl stats set enable 1
ispctl stats set region 3      # 0/1/2/3: 中心 1/4、1/2、3/4、全帧
ispctl stats set black 52
ispctl set blc 0               # 仅新版工具支持；影子值，需 apply
ispctl set blc 1
ispctl set tone 0              # 仅新版工具支持；影子值，需 apply
ispctl set tone 1
ispctl set mode ltm            # ltm/global/raw/identity
ispctl set black 52
ispctl set gain 256            # 细节增益 Q8
ispctl set sigma 64            # 32/64/128
ispctl apply
ispctl curve-default
ispctl curve-load /tmp/curve.txt
ispctl apply --swap
ispctl read 0x34 4
ispctl write 0x18 256          # 原始写仍需 apply

tnrctl status
tnrctl set enable 0            # 影子值，需 apply；enable/bypass 会自动提交
tnrctl set enable 1
tnrctl set alpha 192
tnrctl set motion-low 6
tnrctl set motion-high 20
tnrctl apply
tnrctl clear
tnrctl enable
tnrctl bypass
tnrctl memtest                 # 需先旁路，满足校准和空闲条件
tnrctl read 0x40 4
tnrctl write 0x14 192

# 仅安装 RAW 调试驱动与工具的匹配镜像可用；不据 NV12 验证推定 RAW 已验收
rawctl capture /tmp/frame.raw
raw10check /tmp/frame.raw
```

完成 ISP 配置和提交后，需要恢复自动曝光时执行：

```sh
ibex_isp_handoff start --ps-writers-stopped
ibex_isp_handoff status
```

平台只读诊断：

```sh
cat /tmp/sc130-platform.log
dmesg | grep -i -E 'sc130|vdma|allegro|vcu'
ls -l /dev/sc130-nv12 /dev/sc130_raw10 /dev/video*
cat /sys/devices/system/cpu/online
cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq
head -n 2 /proc/stat
cat /proc/interrupts
cat /etc/sc130-platform.conf /etc/sc130-nv12.conf
```

NV12 专用探测（第二条必须先让现有 USB 编码会话停止、释放 capture；不要与 bridge 竞争独占设备）：

```sh
nv12_vcu_probe --layout-only
nv12_vcu_probe 120 /tmp/probe.h264
```

正常启动由 `/opt/sc130/start-platform.sh` 管理：先加载 VCU/capture，再加载 `/opt/sc130/sc130_nv12.ko`。`/etc/sc130-nv12.conf` 在原平台配置后读取，设置 `SC130_USE_NV12=1`、`UVC_FORMAT=h264`。bridge 接收 `--nv12 /dev/sc130-nv12`；请求 NV12 后失败不自动回退 CPU 转换。裸机/旧 bitstream 缺少 A0080000 时不要加载新驱动。

```sh
# 下列是启动参数说明，不要在已运行实例旁再启动一个 bridge
sc130_platform_bridge --usb-format h264 --nv12 /dev/sc130-nv12
# 请求现有 bridge 保存最近的 YUY2 显示源；不是 NV12 编码输入
kill -USR1 "$(pidof sc130_platform_bridge)"
```

USB gadget prepare/绑定、soft_connect 和 bridge 生命周期由启动脚本统一管理。旧 `setup_uvc.sh run [bridge options]`、旧 `build.sh`、`stage-frame` 和 `flash-boot` 的安装与实现不属于当前通用板端控制接口；不沿用其地址/参数作新版烧录说明。本文不提供 QSPI 写入命令，本次 NV12 验证没有烧写 QSPI。

旧 GPIO bit-bang `sensorctl`/`sc130_config_runtime` 不参与当前 Ibex 原生 I2C 的所有权协议，不要与其并发访问 sensor。更换 sensor 后还需核对初始化、时序和寄存器，不应将具体型号寄存器写入通用命令表。

## 当前权威源码与验证边界

以下路径均相对 `E:/workspace/AI_Projects/RISC_V/ibex`：

- `platform/zu4ev/isp/ltm/isp_axi_regs.sv`：ISP/RAW 统计寄存器；`software/isp-control/ispctl.c` 为实际 CLI。
- `platform/zu4ev/isp/tnr/` 与 `software/tnr-control/tnrctl.c`：TNR 接口。
- `integration/small/rtl/ibex_isp_cfg_owner.sv`、`platform/zu4ev/software/ibex_isp_handoff.c`：控制交接。
- `platform/zu4ev/isp/nv12/REGISTERS.md`、`linux/kernel/sc130_nv12.c`：NV12 ABI/生命周期。
- `platform/zu4ev/linux/start-platform.sh`、`hardware/add_nv12.tcl`、`linux/dt/sc130-nv12.dts`：启动、地址和中断。
- `platform/zu4ev/isp/nv12/BOARD_TEST.md`：RAM 上板结果；本次文档整理未重新执行硬件写命令。

NV12 版本已验证 VCU DMA-BUF 导入和两轮 USB 接收解码；完整实现 WNS +0.033 ns、WHS +0.010 ns。长时间稳定性、实际色度与 A53 的逐字节对照和 NV12 QSPI 冷启动仍未验收。命令是否存在取决于所启动镜像，源码支持不代表旧 QSPI 镜像已经更新。
