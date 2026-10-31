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
  la t0, __data_load
  la t1, __data_start
  la t2, __data_end
1: bgeu t1,t2,2f
  lw t3,0(t0)
  sw t3,0(t1)
  addi t0,t0,4
  addi t1,t1,4
  j 1b
2: la t1,__bss_start
  la t2,__bss_end
3: bgeu t1,t2,4f
  sw zero,0(t1)
  addi t1,t1,4
  j 3b
4: call main
5: j 5b
.balign 256
trap:
  li t0,0x0023f83c
  li t1,0xbad0ae00
  sw t1,0(t0)
  csrr t1,mcause
  sw t1,4(t0)
  j 5b
