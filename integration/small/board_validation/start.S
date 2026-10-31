.section .vectors,"ax"
.option norvc
.org 0x80
.global _start
_start:
  la sp, __stack_top
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  la t0, trap
  csrw mtvec, t0
  csrw mie, zero
  call main
1: j 1b
.balign 256
trap:
  li t0, 0x0023f000
  csrr t1, mcause
  sw t1, 0x54(t0)
  csrr t1, mepc
  sw t1, 0x58(t0)
  csrr t1, mtval
  sw t1, 0x5c(t0)
  lw t1, 0x14(t0)
  ori t1, t1, 64
  sw t1, 0x14(t0)
  sw zero, 0x18(t0)
  li t1, 8
  sw t1, 0x0c(t0)
  fence iorw, iorw
  j 1b
