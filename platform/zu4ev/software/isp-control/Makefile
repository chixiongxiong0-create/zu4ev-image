CC = aarch64-linux-gnu-gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror
LDFLAGS ?= -static
OUT ?= ../../build/ae_stats/software
all: $(OUT)/ispctl $(OUT)/sensorctl $(OUT)/ffcctl $(OUT)/dpcctl
$(OUT):
	mkdir -p $@
$(OUT)/%: %.c | $(OUT)
	$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@
.PHONY: all


$(OUT)/sensorctl: sensor_exposure.h
HOSTCC ?= cc
HOST_OUT ?= ../../build/sensor_exposure/host
test:
	mkdir -p $(HOST_OUT)
	$(HOSTCC) $(CFLAGS) sensorctl.c -o $(HOST_OUT)/sensorctl
	$(HOSTCC) $(CFLAGS) ispctl.c -o $(HOST_OUT)/ispctl
	$(HOSTCC) $(CFLAGS) test_exposure.c -o $(HOST_OUT)/test_exposure
	$(HOST_OUT)/test_exposure
	python3 test_sensor_host.py $(HOST_OUT)/sensorctl
	python3 test_host.py $(HOST_OUT)/ispctl
.PHONY: test
