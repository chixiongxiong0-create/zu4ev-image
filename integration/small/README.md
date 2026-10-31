# Ibex small + 256 KiB ROM / 256 KiB RAM

本目录提供独立的可综合 SystemVerilog 封装，以及 Vivado 2025.1 XSim 自检。
上游 Ibex RTL 不作修改。small 参数逐项对应根目录 `ibex_configs.yaml`，
使用 RV32IMC、两级流水线、RegFileFF，无指令缓存、PMP 或 SecureIbex。

## 集成入口

- `rtl/ibex_small_core.sv`：CPU 原生指令/数据接口封装。适合项目自行连接存储与总线。
- `rtl/ibex_small_mem.sv`：256 KiB ROM 与 256 KiB RAM。
- `rtl/ibex_small_system.sv`：CPU 与上述存储的组合顶层，固定启动基址。
- `sources.txt`：按依赖顺序列出的上游文件，路径相对于仓库根目录。

ZU4EV 工程加入 `sources.txt` 中的文件和 `rtl/*.sv`，添加以下 include 目录：
`vendor/lowrisc_ip/ip/prim/rtl`、`vendor/lowrisc_ip/dv/sv/dv_utils`。
定义 `SYNTHESIS`、`FPGA_XILINX`。仿真也应明确设置这两个宏：它们禁用未使用的
Verilator DPI 导出等上游辅助代码，避免 XSim 2025.1 生成非法 C 函数名。
Vivado 自动依赖扫描无法完整识别该版本部分 package-import 模块，脚本使用
`source_mgmt_mode None` 并显式加入已排序文件。
时钟门控使用上游 `prim_xilinx` 实现，仿真需要 Vivado 的 `unisims_ver` 库。

## 地址与时序

| 地址范围 | 大小 | 访问 |
| --- | --- | --- |
| `0x00100000–0x0013FFFF` | 256 KiB | 指令读取、数据读取；写入返回错误 |
| `0x00200000–0x0023FFFF` | 256 KiB | 数据读写，支持四个字节使能 |

CPU 从 `0x00100080` 执行。ROM 可通过 `RomFile` 设置完整的 65536 行、每行8位
十六进制字符的32位小端字镜像。程序常量可通过数据端读 ROM。
RAM 不预先清零，软件必须初始化需要使用的区域；复位不改变 ROM/RAM 内容。
存储模块按字索引访问，低两地址位由 CPU 的字节使能/LSU管理。
获准请求在采样时钟沿后返回 `rvalid` 和读数据/错误；支持连续每拍请求。
请求、grant、rvalid 没有响应反压。非法地址产生单次错误响应，数据值不规定。

ROM 两个同步读口、RAM 同步读和字节写，无阵列复位，带 BRAM 推断属性。
本次仅完成行为仿真，尚未确认综合后的 BRAM 资源和时序结果。

系统顶层 `clk_i/rst_ni` 由集成方提供（复位应异步置位、同步释放）。
中断/debug 输入必须处于同一时钟域，未使用时置零。`debug_req_i` 只引出CPU请求，
未包含 Debug Module 或调试ROM；未提供AXI桥或通用外设窗口。
如果需要 PS/AXI 控制、UART、共享RAM或调试模块，应在原生core边界继续集成。

## 重复验证

在仓库根目录 PowerShell 运行（附带预编译 ROM 镜像，无需先安装交叉编译器）：

```powershell
powershell -ExecutionPolicy Bypass -File integration/small/tools/run_xsim.ps1
```

可用 `-Vivado` 参数指定其他 Vivado 安装路径。脚本只有同时检查到 CPU 和存储器
两个 PASS 标记且无 Fatal/Error 才成功；失败不以 Vivado 的零退出码作为通过依据。
工程和仿真结果位于 `build/ibex_small/xsim`。

修改自检汇编后，在本机已配置的 WSL 环境中重建 ROM：

```powershell
wsl -d Ubuntu-24.04 -- bash /mnt/e/workspace/AI_Projects/RISC_V/ibex/integration/small/tools/build_firmware.sh
```

`sw/selftest.mem` 是可综合ROM初始化数据，不包含板卡状态。
工具脚本复用 `D:\development\rtl` 下的工具环境。

## 验证范围

CPU 实际执行 ROM 程序，完成 RAM 首末字、字节/半字读写、ROM常量、乘除法、
压缩指令、非法 load 异常与 ROM 写异常，写出 `0x600D600D`。
独立存储测试覆盖16种字节掩码、首末地址、邻接越界、ROM写保护及复位应答清除、
RAM复位后内容保持。20000周期超时即失败。
这不是完整 ISA 合规认证、UVM回归或板上验证。


## Shared RAM / AXI4-Lite and AE shadow boundary

RAM now uses Xilinx xpm_memory_tdpram (256 KiB). Port A serves Ibex; port B serves a 32-bit AXI4-Lite reader. Addresses remain absolute byte addresses 0x00200000..0x0023ffff. Only word-aligned reads succeed; invalid/unaligned reads return SLVERR and zero. Set Vivado XPM_LIBRARIES to XPM_MEMORY. CPU and AXI use the same clock/reset; external clock domains require an AXI Clock Converter and coordinated reset.

One AXI read may be outstanding. RDATA/RRESP/RVALID hold under backpressure. AW and W may arrive independently in either order; each pair returns SLVERR, with BVALID held until BREADY. No AXI write changes RAM. PROT and WSTRB do not override write rejection; access protection belongs in the system interconnect. CPU writes and AXI reads of different words can run concurrently. A same-cycle same-word CPU write stalls AR acceptance, avoiding undefined cross-port collision values. Continuous CPU writes to that word can starve AXI. Reset discards pending AXI transactions without clearing RAM; masters must discard pre-reset transactions.

This is shared-memory infrastructure only: AE firmware has NOT been ported. The read-only AXI port cannot feed statistics into Ibex. A subsequent ZU4EV integration must define the statistics input path, state initialization and result layout. R5 remains the sole IIC owner in shadow mode; Ibex must not write sensors. Compare outputs from the same frame input and the same initial state. Publish coherent snapshots using a single-writer odd/even version protocol: write odd version, update frame/state/results, then write even version. Reader checks version before and after reading and accepts only equal even versions; otherwise retry. PS firmware must handle cache coherency and memory barriers, and version rollover must not occur during one snapshot read. The current self-test does not implement AE snapshot publishing.


## MiniZU board self-test

See [board/README.md](board/README.md). The actual100MHz ZU4EV test uses256KiB UltraRAM RAM, preserving the original copied AE hardware/interfaces and original ILA depths. JTAG hardware reads confirmed600d600d/abcd5578/deadbeef; this validates CPU self-test, not AE firmware migration. Full linked resources are close to the BRAM limit; rebuild and check timing/resources after firmware changes. The reusable system defaults to block memories; the board wrapper selects both RamPrimitive="ultra" and ProgramPrimitive="ultra". Program UltraRAM is filled from a compact initialized BRAM image before CPU reset release; see board/README.md for startup and image staging.
