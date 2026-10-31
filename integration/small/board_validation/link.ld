ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0x00100000, LENGTH = 256K
         RAM (rwx) : ORIGIN = 0x00200000, LENGTH = 248K }
SECTIONS {
 .vectors : { KEEP(*(.vectors)) } >ROM
 .text : { *(.text*) *(.rodata*) . = ALIGN(4); } >ROM
 .data : { *(.sdata*) *(.data*) } >RAM AT>ROM
 .bss (NOLOAD) : { *(.sbss*) *(.bss*) *(COMMON) } >RAM
 __global_pointer$ = ORIGIN(RAM)+0x800;
 __stack_top = ORIGIN(RAM)+LENGTH(RAM);
 ASSERT(SIZEOF(.data)==0, "validation startup requires no initialized RAM data")
 ASSERT(SIZEOF(.bss)==0, "validation startup requires no bss")
}
