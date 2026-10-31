.section .text
.option norvc
.org 0x80
.global _start
_start:
  li s4, 1
  la t0, trap
  csrw mtvec, t0
  li s0, 0x00200000
  li s1, 0x0023fffc
  li t0, 0x12345678
  sw t0, 0(s0)
  lw t1, 0(s0)
  bne t0, t1, fail
  li t0, 0xdeadbeef
  li s4, 2
  sw t0, 0(s1)
  lw t1, 0(s1)
  bne t0, t1, fail
  li t0, 0x55
  li s4, 3
  sb t0, 1(s0)
  li t0, 0xabcd
  sh t0, 2(s0)
  lw t1, 0(s0)
  li t0, 0xabcd5578
  bne t0, t1, fail
  la t0, constant
  li s4, 4
  lw t1, 0(t0)
  li t0, 0xcafebabe
  bne t0, t1, fail
  li t0, 7
  li s4, 5
  li t1, 9
  mul t2, t0, t1
  li t3, 63
  bne t2, t3, fail
  div t2, t2, t1
  bne t2, t0, fail
  .option rvc
  c.addi t0, 1
  .option norvc
  li t1, 8
  bne t0, t1, fail
  li s2, 0
  li s4, 6
  li s3, 5
  li t0, 0x00240000
  lw t1, 0(t0)
  li s3, 7
  li s4, 7
  li t0, 0x00100000
  sw zero, 0(t0)
  li t0, 2
  bne s2, t0, fail
  li t0, 0x600d600d
  sw t0, 16(s0)
1: j 1b
fail:
  sw s4, 20(s0)
  sw t4, 24(s0)
  li t0, 0xbad00bad
  sw t0, 16(s0)
2: j 2b
.balign 256
trap:
  csrr t4, mcause
  bne t4, s3, fail
  addi s2, s2, 1
  csrr t4, mepc
  addi t4, t4, 4
  csrw mepc, t4
  mret
.balign 4
constant: .word 0xcafebabe
