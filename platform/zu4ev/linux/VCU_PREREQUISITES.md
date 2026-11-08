# Upstream VCU encoder prerequisites

The selected application API is upstream `allegro` V4L2 memory-to-memory,
not the downstream `al5e` character-device API. Enable
`CONFIG_MEDIA_SUPPORT`, `CONFIG_VIDEO_DEV`, `CONFIG_V4L_MEM2MEM_DRIVERS`,
`CONFIG_VIDEO_ALLEGRO_DVT=m` and the ZynqMP VCU clock provider
`CONFIG_XILINX_VCU=m`. Enabling the clock provider alone creates no encoder.
Build/install modules against the running kernel and run depmod.

The matching kernel's `drivers/media/platform/allegro-dvt/allegro-core.c`
accepts NV12 input and H.264/HEVC output. It accepts a rational frame rate in
VIDIOC_S_PARM without a driver-side maximum; acceptance of 120/1 does not prove
120 fps throughput. Packed YUY2 is not a supported encoder input. Preserve the
DP capture buffers and convert into separate NV12 storage. A53 conversion and
end-to-end 1280x1024@120 throughput require board measurements.

Install legally obtained matching firmware in `/lib/firmware`: `al5e_b.fw`
(MCU) and `al5e.fw` (codec). The checked driver recognizes only these byte-size
pairs: v2018.2 18296/96272 and v2019.2 14680/126572. These are size checks,
not cryptographic integrity checks. Modern VCU SDK firmware is not an implicit
substitute. Firmware binaries are not included here.

Device tree must follow the matching kernel bindings
`media/allegro,al5e.yaml` and `clock/xlnx,vcu.yaml`, plus the VCU settings syscon
binding. Encoder compatible is `allegro,al5e-1.1`, `allegro,al5e`; register
resources are named `regs` (0x1000) and `sram` (0x8000). Required clock names:
`core_clk`, `mcu_clk`, `m_axi_core_aclk`, `m_axi_mcu_aclk`,
`s_axi_lite_aclk`. Derive addresses, reference clocks and interrupt from the
validated XSA. Do not copy the binding example addresses into this platform.
Do not bind both downstream and upstream encoder drivers to one VCU.

Installed Vivado 2025.1 metadata identifies `xilinx.com:ip:vcu:1.2` and the
interfaces `S_AXI_LITE`, `M_AXI_ENC0`, `M_AXI_ENC1`, `M_AXI_MCU`. Encoder-only
configuration must connect all enabled masters to DDR, control AXI, interrupt,
`s_axi_lite_aclk`, `m_axi_mcu_aclk`, `m_axi_enc_aclk`, PLL reference and reset.
Clock/reset configuration must pass the installed IP's clock checks and BD
validation. This document does not establish a validated hardware integration.

Acceptance: verify firmware initialization and `/dev/video*` driver identity,
enumerate NV12/H.264 formats, encode/decode a known image, then measure 120 fps
with DP active and repeated USB stream stop/start. Record CPU use, frame counts,
latency, decoder errors and buffer ownership failures. No board programming is
performed by this prerequisite document.

## Rebuild and runtime staging

Run in Ubuntu WSL from the repository root:

```sh
bash platform/zu4ev/linux/build_h264_kernel.sh > /home/developer/zu4ev/sc130-h264-build/rebuild.log 2>&1
bash platform/zu4ev/linux/stage_h264_runtime.sh
```

The script applies the repository patches idempotently to the matching existing
kernel source; its output is independent of the validated baseline kernel output.
`SC130_KERNEL_SOURCE`, `SC130_BASE_KERNEL_OUT`, and `SC130_H264_KERNEL_OUT` can
select explicitly prepared matching trees. Do not build concurrently against
the same source/output. Kernel output contains `arch/arm64/boot/Image`,
`sc130-h264.dtb`, capture modules, and the runtime overlay. The dedicated
`minimal-overlay` stages only `allegro.ko`, `xlnx_vcu.ko`, their depmod metadata,
the rebuilt capture modules, UVC/startup scripts and matching firmware/license.
The selected configuration builds remaining V4L2/vb2 dependencies into Image.

Firmware retrieval uses the official `Xilinx/vcu-firmware` revision
`29ab982965b797b1c9b567faba47378578398f4a`, selected by AMD's rel-v2019.2
meta-xilinx recipe. `fetch_vcu_firmware.py` validates both exact sizes and pinned
SHA256 hashes, preserves LICENSE, and writes a provenance manifest. The blobs
are generated build inputs rather than tracked repository binaries.

Patch 0010 compacts non-I encoder partitions to byte zero: single-planar V4L2
does not expose vb2 `data_offset` to userspace. I/IDR frames retain generated
parameter sets and filler. This patch is required with the single-planar backend.
