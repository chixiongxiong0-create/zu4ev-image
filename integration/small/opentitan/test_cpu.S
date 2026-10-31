.section .text
.option norvc
.org 0x80
.global _start
_start:
 li s0, 0x00200000
 li s1, 0x40030000
 li t0, 0x5a3c
 sw t0, 0(s0)
 sw t0, 0x14(s1)
 li t1, 0xff
 sw t1, 0x20(s1)
 lw t2, 0x14(s1)
 bne t2,t0,fail
 lw t2,0(s0)
 bne t2,t0,fail
 li s1, 0x40000000
 li t0,1
 sw t0, 0x100(s1)
 sw t0, 0x108(s1)
 li s1, 0x40010000
 lw t0, 0(s1)
 li s1, 0x40020000
 lw t0, 0x14(s1)
 li t0, 0x600d600d
 sw t0, 0x10(s0)
1: j 1b
fail:
 li t0, 0xdeadbeef
 sw t0, 0x10(s0)
 j fail
