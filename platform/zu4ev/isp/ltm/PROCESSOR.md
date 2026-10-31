> Live integration and AXI-Lite runtime controls: see [ISP control](../../docs/isp-control/README.md). Static parameters below describe the original standalone tests.

# 固定基础层曲线的 LTM 处理器

`ltm_processor.sv`将已有保边分层补齐为RAW10→YUY2的独立处理链：

```text
RAW10两像素
 → 黑位52扣除、负值置零
 → 5×5双边滤波，B为基础层、D=I−B
 → 双读口BRAM ROM计算T(B)，内部保留10位
 → O=clip(T(B)+round(g×D),0,1023)
 → 16～235有限范围Y，U=V=128，打包Y0/U/Y1/V
```

这是固定曲线的局部基础层/细节层处理，不包含场景直方图自适应。
5×5窗口侧重局部细纹理，不等同于大尺度光照估计。
已验证的`bilateral_layers.sv`等分层RTL未修改。

## 参数与接口

| 参数 | 默认值 | 含义 |
|---|---:|---|
| WIDTH / HEIGHT | 1280 / 1024 | 图像尺寸；偶数宽4～2048，高至少5 |
| DETAIL_GAIN_Q8 | 256 | 细节强度，实际增益为参数/256，支持0～512 |
| BYPASS | 0 | 设为1时输出原始RAW线性有限范围映射，保留相同空间流水与流控 |
| IDENTITY | 0 | 诊断模式，基础层映射T(B)=B；增益256时O等于黑位校正输入 |

DETAIL_GAIN_Q8=0仅保留映射后的基础层；128为0.5倍细节，256为1倍，512为2倍。
负数和正数均按最近值舍入，恰好半整数时向远离零方向舍入。
参数是综合期配置，不是运行时寄存器。

输入与`bilateral_layers`相同，低10位是左像素、高10位是右像素。
输出`m_data[31:0]`内存字节顺序为Y0、128、Y1、128。
`m_valid/m_ready/m_sof/m_eol`与输出数据对齐，暂停时全部保持。

调试输出与`m_data`严格对齐：

- `m_original[19:0]`：正常/恒等模式下为扣黑位后的输入；BYPASS模式下为未扣黑位输入。
- `m_base[19:0]`：两路10位基础层。
- `m_detail[21:0]`：两路11位有符号细节层。
- `m_reconstructed[19:0]`：两路10位重建结果，已经限幅，尚未量化为视频Y。

恒等模式只验证重建，不执行白点971→1023归一化，因此其白输出不要求达到235。
BYPASS与原始线性RAW10→YUY2映射一致；它用于数值对照，不消除行缓存延迟。

## 曲线与BRAM

黑位校正后有效白点为971。曲线沿用原ISP的9个分段控制点，但从控制点
直接生成10位输出，没有先量化成8位再放大：

| 输入百分比 | 0 | 1 | 4 | 10 | 25 | 50 | 75 | 90 | 100 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 参考视频Y | 16 | 22 | 49 | 82 | 128 | 176 | 208 | 224 | 235 |

内部T=(Y−16)×1023/219；插值与舍入一次完成。输入超过971映射到1023。
曲线只作用于基础层一次。输出不能再串联旧的`raw10_to_yuy2`曲线，否则会重复映射。

除了五组行缓存IP，新增`ltm_tone_rom`双读口BMG ROM，10×1024、每路一拍读延迟。
ROM与元数据共用流水暂停使能，复位丢弃旧有效事务，ROM不需要清空。

生成与加入工程：

```powershell
python isp/ltm/generate_tone_rom.py
```

```tcl
source -notrace /absolute/path/to/isp/ltm/create_ip.tcl
source -notrace /absolute/path/to/isp/ltm/create_tone_ip.tcl
add_files [list /absolute/path/to/isp/ltm/unsigned_divider.sv \
                /absolute/path/to/isp/ltm/bilateral_kernel.sv \
                /absolute/path/to/isp/ltm/bilateral_layers.sv \
                /absolute/path/to/isp/ltm/ltm_processor.sv]
set_property include_dirs [list /absolute/path/to/isp/ltm] [get_filesets sources_1]
```

`base_tone.coe`和`base_tone.json`记录系数及生成身份。
两份IP创建脚本用于新工程；同名IP已有时应先检查并复用，不能重复创建ROM实例定义。

## 复跑

```powershell
./sim/ltm/run_processor.ps1 -Case all
python sim/ltm/plot_processor.py --vectors build/ltm_processor/vectors_full --out reports/ltm_processor/full
& D:/Xilinx/2025.1/Vivado/bin/vivado.bat -mode batch -source sim/ltm/synth_processor.tcl
```

参考模型只需Python标准库，绘图另外需要NumPy、Matplotlib。
XSim使用实际BMG RAM/ROM模型。测试平台另外例化一个只用于验证的ROM，
以独立参考系数穷举两个端口的全部1024个地址；这个验证实例不属于综合顶层。

实际输出`actual.mem`每行116位、29个十六进制字符：
bit115 SOF、114 EOL、113:82 YUY2、81:62重建、61:42校正输入、41:20细节、19:0基础层。
脚本核对实际输出文件数量，绘图从该文件取图像，不把软件参考结果当RTL输出。

## 使用边界

内部T(B)+gD可能超出0～1023，此时限幅；饱和区无法保证细节不损失。
测试包含有意触发高光裁剪及恒等曲线下的暗部裁剪，裁剪数在报告中单列。
细节增益过大也会增强噪声，尚无噪声自适应门限。

当前仍为独立模块，未接入`isp.v`，未生成摄像头bitstream或烧录。
后续接入时需保留BLC顺序，避免重复曲线，并处理传感器不接受背压、行末/帧末排空、
SOF/EOL及采集故障元数据的同步。只有完成布局布线和板测后才能评价实际帧率与画质。

结果与实际输出对比图见`reports/ltm_processor/results.md`。
