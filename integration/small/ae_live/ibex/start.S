.section .vectors,"ax"
.option norvc
.org 0x80
.global _start
_start:
  la sp,__stack_top
.option push
.option norelax
  la gp,__global_pointer$
.option pop
  la t0,trap_vectors
  ori t0,t0,1
  csrw mtvec,t0
  la t0,__data_load
  la t1,__data_start
  la t2,__data_end
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
trap_vectors:
  # Ibex implements vectored mtvec only. Exceptions enter slot 0 and IRQ17
  # enters slot 17; every slot must jump to the complete save/restore entry.
  .rept 32
  j trap_entry
  .endr
  .balign 256
trap_entry:
  addi sp,sp,-64
  sw ra,0(sp)
  sw t0,4(sp)
  sw t1,8(sp)
  sw t2,12(sp)
  sw t3,16(sp)
  sw t4,20(sp)
  sw t5,24(sp)
  sw t6,28(sp)
  sw a0,32(sp)
  sw a1,36(sp)
  sw a2,40(sp)
  sw a3,44(sp)
  sw a4,48(sp)
  sw a5,52(sp)
  sw a6,56(sp)
  sw a7,60(sp)
  csrr a0,mcause
  li t0,0x80000011
  bne a0,t0,6f
  call ae_irq_handler
  j 7f
6: csrr a1,mepc
  call ae_trap_handler
7: lw ra,0(sp)
  lw t0,4(sp)
  lw t1,8(sp)
  lw t2,12(sp)
  lw t3,16(sp)
  lw t4,20(sp)
  lw t5,24(sp)
  lw t6,28(sp)
  lw a0,32(sp)
  lw a1,36(sp)
  lw a2,40(sp)
  lw a3,44(sp)
  lw a4,48(sp)
  lw a5,52(sp)
  lw a6,56(sp)
  lw a7,60(sp)
  addi sp,sp,64
  mret
