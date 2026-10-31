> Live integration and AXI-Lite runtime controls: see [ISP control](../../docs/isp-control/README.md). Static parameters below describe the original standalone tests.

# 5×5 双边滤波保边分层 RTL

完整固定曲线处理链已新增：`ltm_processor.sv`，用法见[PROCESSOR.md](PROCESSOR.md)，
最新验证见`reports/ltm_processor/results.md`。下文描述原始分层模块。

这是 Local Tone Mapping 的**分层阶段**：输入 I，输出基础层 B 与有符号
细节层 D，满足 `I = B + D`。未执行基础层亮度压缩，也未接入现有摄像头采集通路。

## 文件

| 文件 | 职责 |
|---|---|
| `bilateral_layers.sv` | 双像素流接口、五组行缓存、5×5窗口和边界排空 |
| `bilateral_kernel.sv` | 双边权重、分级累加、基础层与细节层输出 |
| `unsigned_divider.sv` | 10级流水定点无符号除法，每级可暂停 |
| `range_lut.svh` | 灰度差高斯权重，8位量化，编译成逻辑常量 |
| `generate_range_lut.py` | 重建或使用`--check`核对固定sigma_r=64的LUT |
| `create_ip.tcl` | 生成和回读验证 `ltm_line_bram` BMG IP |

## 算法与精度

对5×5邻域逐点计算，非普通均值滤波，也非横纵两次近似双边滤波：

```
S = outer([1,4,6,4,1], [1,4,6,4,1])
R(d) = floor(255 * exp(-d*d/(2*64*64)) + 0.5)
w(q) = S(q) * R(abs(I(q)-I(center)))
B = floor((sum(w*I) + floor(sum(w)/2)) / sum(w))
D = I(center) - B
```

空间核近似 sigma_s=1像素；sigma_r=64 RAW10码值。该窗口只分离局部纹理，
不是宽尺度光照估计。参数变更需要重新生成权重并验证，不提供运行时调参。
中心权重固定非零，分母不为零。分母最大65280，26位分子含舍入后最大66814080，
均无溢出。B为10位，D每像素为11位二补码。

## 流接口

- `WIDTH=1280, HEIGHT=1024` 默认；支持偶数宽4～2048，高度至少5。
- `s_data[9:0]` 为左像素，`[19:10]` 为右像素。
- `m_original`、`m_base` 按相同10位通道打包。
- `m_detail[10:0]`、`[21:11]` 分别为左右像素的**有符号11位值**；
  使用 `$signed(m_detail[10:0])` 取值，不能把整个22位总线当成一个有符号数。
- 只在 `valid && ready` 时接受事务。输出暂停时，数据、SOF/EOL与所有流水级保持。
- SOF必须位于每帧首对像素，EOL位于每行末对；输入帧必须完整且尺寸匹配。
  输出标记由尺寸计数生成，输入标记用于仿真契约检查，不用于硬件自动重同步。
- 同步低有效复位丢弃正在处理的帧；重新输入从SOF开始的完整帧即可。
- 四边使用复制边界。每行末自动补一个双像素拍，帧末自动补两行。
  不依赖下一帧输入即可输出最后两行。排空期间会拉低`s_ready`。
- 无停顿时每个有效输出拍两个像素。每帧窗口调度需
  `(HEIGHT+2)*(WIDTH/2+1)` 拍，另有固定流水延迟；这不等于整个帧周期始终无间断。
- 算术核13级；BRAM读取与窗口构造在其前面。背压会增加墙钟延迟。

传感器原始入口不支持暂停，因此后续接入`isp.v`前，需要核对FIFO与消隐预算、
帧末排空时间及packet_error/global_fault延迟。当前没有修改这些集成逻辑。

## BRAM IP

五个 `ltm_line_bram` 显式例化，均由 **Block Memory Generator** 生成，
每组20位×1024深度。A口写、B口读，共同时钟，关闭两级可选读输出寄存器，
同步读延迟一拍；当前行走旁路，不读取正在写入的bank，避免读写碰撞。
综合确认是5个RAMB36E2，不使用自写RAM模型替代IP验证。

在目标Vivado工程中：

```tcl
source -notrace /absolute/path/to/isp/ltm/create_ip.tcl
add_files [list /absolute/path/to/isp/ltm/unsigned_divider.sv \
                /absolute/path/to/isp/ltm/bilateral_kernel.sv \
                /absolute/path/to/isp/ltm/bilateral_layers.sv]
set_property include_dirs [list /absolute/path/to/isp/ltm] [get_filesets sources_1]
```

生成的XCI快照见`reports/ltm/*/ltm_line_bram.xci`。迁移工程推荐使用生成脚本，
由本机Vivado选择可用IP版本；不需要硬编码IP修订版本。

## 复现验证

在仓库根目录的PowerShell中：

```powershell
./sim/ltm/run.ps1 -Case all
# 指定安装路径时：
./sim/ltm/run.ps1 -Case small -VivadoBin D:/Xilinx/2025.1/Vivado/bin
```

Python参考计算只依赖标准库；仿真必须使用Vivado自带XSim及BMG库。
`run.tcl`建立独立测试工程，不打开摄像头工程。`actual.mem`记录RTL输出，
不是参考模型生成的图像。绘图需要本机NumPy、Matplotlib：

```powershell
python sim/ltm/plot_results.py --vectors build/ltm/vectors_full --out reports/ltm/full
```

可选综合资源检查，在small测试创建工程后执行：

```powershell
& D:/Xilinx/2025.1/Vivado/bin/vivado.bat -mode batch -source sim/ltm/synth.tcl
```

综合报告只作为资源与结构证据，不代表布局布线时序收敛。
完整结果见`reports/ltm/results.md`。
