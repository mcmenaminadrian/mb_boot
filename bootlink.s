SECTIONS
{
	ENTRY(_start)
	. = 0x0000;
	.vectors.reset : { *(.vectors.reset) }
	. = 0x0008;
	.vectors.sw_exception : { *(.vectors.sw_exception) }
	. = 0x0010;
	.vectors.interrupt : { *(.vectors.interrupt) }
	. = 0x0018;
	.vectors.hw_exception : { *(.vectors.hw_exception) }
	. = 0x100;
	.text : { *(.text) }
	.data : { *(.data) }
	.bss : { *(.bss) }
}
