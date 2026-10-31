CC = aarch64-linux-gnu-gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror
LDFLAGS ?= -static
OUT ?= ../../build/ae_stats/software
all: $(OUT)/tnrctl
$(OUT):
	mkdir -p $@
$(OUT)/tnrctl: tnrctl.c | $(OUT)
	$(CC) $(CFLAGS) $< $(LDFLAGS) -o $@
.PHONY: all
