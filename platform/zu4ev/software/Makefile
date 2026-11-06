CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=c11 -D_DEFAULT_SOURCE -Wall -Wextra -Werror
LDFLAGS ?=
OUT ?= build
BRIDGE_SOURCES = platform_bridge.c uvc_core.c dp_display.c h264_encoder.c
BRIDGE_HEADERS = uvc_core.h dual_core.h dp_display.h capture_broker.h perf_stats.h h264_encoder.h nv12_capture.h
BRIDGE_TESTS = test_platform_events test_snapshot test_usb_marker test_usb_completion test_usb_perf test_usb_shared
TESTS = $(BRIDGE_TESTS) test_perf test_broker dp_ownership_test test_uvc_h264 test_encoder_ownership test_h264_encoder test_h264_bridge test_nv12_encoder
.PHONY: all test clean
all: $(OUT)/nv12_vcu_probe $(OUT)/sc130_platform_bridge $(OUT)/dp_smoke $(OUT)/ibex_isp_handoff
$(OUT):
	mkdir -p $@
$(OUT)/sc130_platform_bridge: $(BRIDGE_SOURCES) $(BRIDGE_HEADERS) | $(OUT)
	$(CC) $(CFLAGS) $(BRIDGE_SOURCES) $(LDFLAGS) -o $@
$(OUT)/dp_smoke: dp_smoke.c dp_display.c dp_display.h | $(OUT)
	$(CC) $(CFLAGS) dp_smoke.c dp_display.c $(LDFLAGS) -o $@
$(OUT)/ibex_isp_handoff: ibex_isp_handoff.c | $(OUT)
	$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@
$(addprefix $(OUT)/,$(BRIDGE_TESTS)): $(OUT)/%: tests/%.c $(BRIDGE_SOURCES) $(BRIDGE_HEADERS) | $(OUT)
	$(CC) $(CFLAGS) $< uvc_core.c dp_display.c h264_encoder.c -o $@
$(OUT)/test_perf: tests/test_perf.c perf_stats.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/test_broker: tests/test_broker.c capture_broker.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/dp_ownership_test: tests/dp_ownership_test.c dp_display.c dp_display.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/test_uvc_h264: tests/test_uvc_h264.c uvc_core.c uvc_core.h | $(OUT)
	$(CC) $(CFLAGS) $< uvc_core.c -o $@
$(OUT)/test_encoder_ownership: tests/test_encoder_ownership.c capture_broker.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/test_h264_encoder: tests/test_h264_encoder.c h264_encoder.c h264_encoder.h uvc_core.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@
$(OUT)/test_h264_bridge: tests/test_h264_bridge.c $(BRIDGE_SOURCES) $(BRIDGE_HEADERS) | $(OUT)
	$(CC) $(CFLAGS) $< uvc_core.c dp_display.c -o $@
test: $(addprefix $(OUT)/,$(TESTS))
	@set -e; for binary in $(addprefix $(OUT)/,$(TESTS)); do "$$binary"; done
clean:
	rm -f $(OUT)/sc130_platform_bridge $(OUT)/dp_smoke $(OUT)/ibex_isp_handoff $(addprefix $(OUT)/,$(TESTS))

$(OUT)/test_nv12_encoder: tests/test_nv12_encoder.c h264_encoder.c h264_encoder.h nv12_capture.h uvc_core.h | $(OUT)
	$(CC) $(CFLAGS) $< -o $@

$(OUT)/nv12_vcu_probe: nv12_vcu_probe.c h264_encoder.c h264_encoder.h nv12_capture.h uvc_core.h | $(OUT)
	$(CC) $(CFLAGS) nv12_vcu_probe.c h264_encoder.c $(LDFLAGS) -o $@
