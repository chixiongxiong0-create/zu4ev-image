.section .text
.option norvc
.org 0x40
 j handler
.org 0x80
.global _start
_start:
 li s0, 0x00200000
 li s1, 0x40020000
 li s2, 0
 li t0, 0x00100001
 csrw mtvec, t0
 li t0, 0x10000
 csrw mie, t0
 li t0, 8
 csrs mstatus, t0
 li t0, 4
 sw t0, 4(s1)
 sw t0, 8(s1)
1: beqz s2, 1b
 li t0, 0x600d6010
 sw t0, 0x10(s0)
2: j 2b
.balign 4
handler:
 csrr t0, mcause
 li t1, 0x80000010
 bne t0,t1,fail
 li t0,4
 sw t0,0(s1)
 li s2,1
 mret
fail:
 li t0,0xdeadbeef
 sw t0,0x10(s0)
3: j 3b
