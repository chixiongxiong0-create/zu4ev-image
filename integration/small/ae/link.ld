ENTRY(_start)
MEMORY { ROM (rx) : ORIGIN = 0x00100000, LENGTH = 256K
         RAM (rwx) : ORIGIN = 0x00200000, LENGTH = 248K }
SECTIONS {
 .vectors : { KEEP(*(.vectors)) } >ROM
 .text : { *(.text*) *(.rodata*) . = ALIGN(4); } >ROM
 .data : { __data_start = .; *(.sdata*) *(.data*) . = ALIGN(4); __data_end = .; } >RAM AT>ROM
 __data_load = LOADADDR(.data);
 __global_pointer$ = __data_start+0x800;
 .bss (NOLOAD) : { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } >RAM
 __stack_top = ORIGIN(RAM)+LENGTH(RAM);
}
