# Real ISP snapshot interface

EnableIspAccess maps 0x50000000–0x5000007f and reserves fast IRQ bit 1
(cause 17). FE and SOF independently assert the shared level IRQ. R5 remains
owner of FE go[13] ACK and sensor. The board configuration gate defaults to PS
ownership of ISP/statistics configuration; explicit handoff can grant Ibex
access through the separate 0x51000000 window. See [ISP_CONFIG.md](ISP_CONFIG.md).

Word offsets: 00/04 reserved; 08 result sequence; 0c result frame; 10 mean;
14 count; 18/1c sum low/high; 20 valid/busy/active bits 0/1/2;
24 region bits 1:0 and black bits 11:2; 28 bad frames; 2c overruns;
30/34 ROI x/y; 38/3c ROI width/height. Offset 40 is full 16-bit FE
sequence, 44 is 14-bit SOF sequence, 48 is pending FE/SOF bits 0/1.
Only 48 is writable: W1C acknowledges counters captured by the most recent
pending-register read. Events after that observation remain pending.
Counters wrap; firmware must service within their wrap interval.

Each read requests a fresh coherent video-clock snapshot. The whole CSR group
is not frozen across reads. Firmware must read result sequence before and after
collecting statistics and retry if it changed. Sum halves use that same rule.
The source values are real ae_stats_raw10 outputs at the capture frontend,
not fixture data. Explicit output ports are added only to the packaged copy.

CDC: source-registered Gray counters pass two receiving synchronizer stages.
The request toggle crosses two source stages; the source captures all statistics
and sequences and acknowledges while holding the payload until another request.
The acknowledgement crosses two receiving stages before the CPU consumes data.
Source reset releases synchronously after two video clocks. Board reset asserts
both sides together; CPU reset restarts the snapshot protocol, without clearing
R5's event counters or statistics. Pending reappears from the live counters.

isp_snapshot_cdc.tcl runs in implementation's OPT_DESIGN pre-hook. It selects
registers by IBEX_CDC attributes, not absolute hierarchy, and fails on missing
markers or clocks. Gray max delay and bus skew are half the smaller actual
clock period, keeping transitions ordered even with clock drift. The held
payload gets a one receiving-period max delay, leaving one full receiving
cycle before consumption after the acknowledgement synchronizer. Do not apply
broad asynchronous clock-group/false-path exceptions that override these max
delays. Review timing exceptions, CDC and constrained paths after synthesis.

Operational limit: video clock must run during an ISP access. A stopped clock
leaves an outstanding read waiting; there is no timeout recovery/cancellation
protocol. Reset both snapshot domains to abandon it before restarting. Firmware
must avoid accesses while camera/video clocks are disabled. The 2026-10-30
routed-board run observed advancing real statistics/FE/SOF and two consistent
firmware publications after stopping firmware polling with `video_ready=0`;
the external video clock continued running. See the board validation report.
This does not validate stopped-clock recovery or simultaneous source sampling
of the statistics and event counters.
