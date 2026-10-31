# Ibex small 集成设计与验收

用户已批准原生指令/数据接口和 ROM/RAM 各 256 KiB。
CPU wrapper 固定使用 ibex_configs.yaml 的 small 参数，保留 RegFileFF。
存储系统 ROM=0x00100000..0x0013ffff，RAM=0x00200000..0x0023ffff。
复位入口为 ROM+0x80。数据端可读 ROM 常量，ROM 写与越界访问返回错误。
每个获准请求在下一周期返回有效响应；同步 ROM 双读，RAM 单端口字节写，
复位只清应答寄存器，不清存储阵列，以支持 FPGA BRAM 推断。
第一版时钟/复位由集成方提供，不涉及板卡引脚或烧写。

实施顺序：原生 small wrapper -> 同步存储模块 -> 仿真固件 -> 自检 TB -> XSim脚本。
验收：真实CPU执行签名；ROM常量读取；RAM首末字、byte/halfword写、乘除法；
直接存储接口边界、非法地址、ROM只读与复位应答检查；超时必须失败。


## Shared RAM / AXI4-Lite and AE shadow boundary

RAM now uses Xilinx xpm_memory_tdpram (256 KiB). Port A serves Ibex; port B serves a 32-bit AXI4-Lite reader. Addresses remain absolute byte addresses 0x00200000..0x0023ffff. Only word-aligned reads succeed; invalid/unaligned reads return SLVERR and zero. Set Vivado XPM_LIBRARIES to XPM_MEMORY. CPU and AXI use the same clock/reset; external clock domains require an AXI Clock Converter and coordinated reset.

One AXI read may be outstanding. RDATA/RRESP/RVALID hold under backpressure. AW and W may arrive independently in either order; each pair returns SLVERR, with BVALID held until BREADY. No AXI write changes RAM. PROT and WSTRB do not override write rejection; access protection belongs in the system interconnect. CPU writes and AXI reads of different words can run concurrently. A same-cycle same-word CPU write stalls AR acceptance, avoiding undefined cross-port collision values. Continuous CPU writes to that word can starve AXI. Reset discards pending AXI transactions without clearing RAM; masters must discard pre-reset transactions.

This is shared-memory infrastructure only: AE firmware has NOT been ported. The read-only AXI port cannot feed statistics into Ibex. A subsequent ZU4EV integration must define the statistics input path, state initialization and result layout. R5 remains the sole IIC owner in shadow mode; Ibex must not write sensors. Compare outputs from the same frame input and the same initial state. Publish coherent snapshots using a single-writer odd/even version protocol: write odd version, update frame/state/results, then write even version. Reader checks version before and after reading and accepts only equal even versions; otherwise retry. PS firmware must handle cache coherency and memory barriers, and version rollover must not occur during one snapshot read. The current self-test does not implement AE snapshot publishing.


## ZU4EV board implementation

Board auxiliary block is independent of camera/PS control buses, runs from existing100MHz lite_clk, and uses16 UltraRAM288 for256KiB data RAM. UltraRAM requires no_change mode on both true-dual ports; CPU store read data is unused. Common-clock, byte-enable and AXI collision/backpressure behavior are covered by the existing focused regression with RamPrimitive="ultra". Source-local UltraScale+ clock-gate binding preserves upstream interface/logic and sets the correct BUFGCE SIM_DEVICE. Board validation uses the copied complete AE design; see RESULTS.md for actual resource and hardware evidence. No AE firmware or sensor-control ownership changes are included.

### Program UltraRAM bootstrap

The board selects a separate 256 KiB program UltraRAM through `ProgramPrimitive`, while default reusable configurations retain initialized block ROM behavior. UltraRAM has no configuration INIT. A compact block boot ROM holds the validated image prefix (`BootImageWords`); a synchronous READ/WRITE copier writes every program word and zero padding before `memory_ready_o` releases CPU and loader reset. Copying takes 131072 clocks. All state is in the CPU clock domain. Global reset restarts copying; CPU reset preserves the loaded image. The final WRITE edge commits word 65535 before readiness rises. Runtime port A arbitrates halted-loader access and instruction fetch, and port B supplies CPU constant reads. One-cycle read/response timing is preserved; loader writes use byte enables and no_change response data is unspecified. The board build derives and stages the compact image; no PS loader connection is introduced.
