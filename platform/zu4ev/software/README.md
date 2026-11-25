# Continuous SC130 DP + USB broker

## VCU H.264 output

The bridge now defaults to `--usb-format h264`, matching the default gadget
configuration. `--encoder /dev/videoN` selects an upstream Allegro V4L2 device;
otherwise only devices reporting driver `allegro` are considered. `--bitrate`
accepts 1000000 through 100000000 bits/s (default 20000000). The negotiated
60/120 fps is passed to VCU, using H.264 baseline profile/level 5.1.

DP and snapshots retain the original YUY2 capture buffers. The encoder reads
these buffers without modifying them and converts into private NV12 buffers
using NEON on AArch64. VCU performs H.264 compression. CPU conversion throughput
on a single A53 has not been established by host/QEMU tests.

Compressed access units are sent in order with variable `bytesused`; the raw
latest-frame dropping policy is not applied to encoded reference frames. USB
backpressure retains encoded output, while unencoded source frames may be
skipped. Disconnect closes the encoder and the next stream requires SPS/PPS/IDR.
Encoder/USB failure must not stop DP/capture. `--profile` includes the format
conversion cost and `H264` counters report encoded output bytes/frames.

Recovery requires **both** `UVC_FORMAT=yuy2` at gadget setup and
`--usb-format yuy2` at bridge startup. Raw diagnostic marker/static options
require this recovery mode. Current H.264 mode requires the matching VCU
hardware, kernel patches 0007–0010, modules and firmware described in
`../linux/VCU_PREREQUISITES.md`; it does not fall back to software compression.

Build in Linux/WSL: `make CC=aarch64-linux-gnu-gcc LDFLAGS=-static all`.
Run native regressions: `make OUT=/tmp/sc130-tests CC=gcc test`.

`build/sc130_platform_bridge` starts capture independently of a USB host. Optional arguments include `--capture /dev/videoN`, `--output /dev/videoN`, `--soft-connect PATH`, `--disable-dp`, and `--snapshot PATH`. SIGUSR1 saves one completed YUY2 frame to `/tmp/sc130-frame.yuy2` by default.

## Optional USB frame-order diagnostic

`--usb-sequence-marker` is **off by default**. It stamps only the UVC output copy, after the completed capture has been copied and before output QBUF. Capture memory, DP scanout and snapshots are unchanged.

In each raw 1280x1024 YUY2 frame, the first eight luma bytes at offsets `0,2,4,6,8,10,12,14` are:

- `53 43 31 30` hexadecimal (ASCII `SC10`).
- The capture source sequence as four little-endian bytes.

The eight interleaved chroma bytes at offsets `1,3,...,15` are set to128. Bytes from offset16 onward are untouched. This changes a tiny visible strip in diagnostic USB video. It is not enabled for production automatically.

For raw host capture, split at2621440 bytes per frame. Check the magic and reconstruct sequence with `Y[4] | Y[5]<<8 | Y[6]<<16 | Y[7]<<24`. Test increasing order using signed32-bit differences to allow wraparound; a positive gap indicates skipped source frames, zero indicates a duplicate, and a negative difference indicates reordered frames. Decode the raw YUY2 bytes before scaling or display processing.


## USB 性能诊断

`sc130_platform_bridge --profile` 在真实摄像头路径上启用分段耗时统计，每秒输出本次USB流累计数据。`cpu_one_core_pct=100` 表示一个CPU核心的时间；它不包含其他内核工作线程的CPU耗时。p50/p95/p99为固定桶的上界，max为实际采样最大值。

- copy_wall / copy_cpu：整帧memcpy墙钟与进程CPU耗时，含少量计时调用开销。
- capture_complete_to_dequeue：驱动软件完成时间戳到用户态取帧，不能称为SOF或曝光延迟。
- dequeue_to_submit：取出当前帧到输出QBUF返回，包含等待发送节奏、复制及QBUF。
- output_qbuf：输出QBUF调用耗时。
- usb_queue_to_return：调用输出QBUF到用户态DQBUF归还，包含内核排队、传输和用户态取完成的调度延迟，不是纯USB线缆时间。
- submit_gap：连续成功提交的时间间隔。


对照时保持同一应用/内核/DP/主机参数，主机使用512MiB采集缓冲，顺序运行真实复制A、冻结对照B、真实复制A2。主机完成退出后才停板端应用，避免人为制造停流错误。统计启动、停止边界与稳态错误须分别解释。结果与条件见 reports/usb_copy_performance_20261022.md。

## Current Ibex bundle USB behavior

Normal USB streaming shares capture DMA-BUFs by default. Capture buffers remain held until both DP and USB complete. `--usb-sequence-marker` and `--profile-static-usb` retain the copy path for diagnostics. Static mode does not validate live camera throughput and must not be enabled for production.
