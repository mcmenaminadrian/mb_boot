SECTIONS
{
	. = 0x0000;
	.vectors.reset : { *(.vectors.reset) }
	. = 0x0008;
	.vectors.sw_exception : { *(.vectors.sw_exception) }
	. = 0x0010;
	.vectors.interrupt : { *(.vectors.interrupt) }
	. = 0x0018;
	.vectors.breakpoint : { *(.vectors.breakpoint) }
	. = 0x0020;
	.vectors.hw_exception : { *(.vectors.hw_exception) }
	.text : { *(.text) }
	.data : { *(.data) }
	.bss : { *(.bss) }
}
