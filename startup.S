/* 	Microblaze start up code
	Copyright Adrian McMenamin <acm538@york.ac.uk>, 2014
	Licensed under GPL v3
*/

	.set PTECNT, 0x20
	.set TLBCNT, 0x08
	.set EX, 0x200
	.set WR, 0x100
	.set VALID, 0x40
	.set PAGE4K, 0x080
	.set PAGE64K, 0x180
	.set PAGE4KMASK, 0xFFFFF000
	.set PAGE64KMASK, 0xFFFF0000
	.set PAGE1M, 0x300	/* 0x380 for 16 MB, 0x300 4MB, 0x280 1MB */
	.set PTE_SIZE, 0x08
	.set PTE_SIZE_HALF, 0x04
	.set SECOND_MAP_PHYS, 0x1000000
	.set SECOND_MAP_VIRT, 0x2000000
	.set STACK_MAP_PHYS, 0xFFFF0000
	.set STACK_MAP_VIRT, 0xFFFF0000
	.set STACK_BOTTOM, 0xFFFFFFFF
	.set FRAME_BASE, 0x8000000
	.set VM_ON, 0x2502
	.set PAGE_SZ, 0x1000
	.set MAXPINNED,	0x03	/* how many pinned TLBs/PTEs */
	.set PTEUSED,	0x100	/* hi word is tlbpointer, lo is Y or N */
	.set PTEMAXED,	0x104
	.set CLOCK_SWEEP, 0x05
	.set DUMMY_ZONE, 0xA0000
	.set PAGE_SIZE, 0x1000
	.set ENTRY_SIZE, 0x01

	.macro switchex
	addi	r5, r5, 0x01
	rsub	r6, r5, r4
	.endm	

	.global _start
	.section .vectors.reset, "ax"
	.align 2
	.ent _start
	.type _start, @function

_start:
	brai	_actualstart
	.end _start

	.section .vectors.sw_exception, "ax"
	.align 2
_vector_sw_exception:
	brai	_exception_handler

	.section .vectors.interrupt, "ax"
	.align 2
_vector_interrupt:
	brai	_interrupt_handler

	.section .vectors.breakpoint, "ax"
	.align 2
_vector_breakpoint:
	brai _handle_breakpoint

	.section .vectors.hw_exception, "ax"
	.align 2
_vector_hw_exception:
	brai	_hw_exception_handler

	.section .text
	.global _actualstart
	.align 4
	.ent _actualstart
	.type _actualstart, @function
	.org 0x100
_actualstart:
	addik	r3, r0, TLBCNT - 1
	ori	r4, r0, MAXPINNED
	swi	r4, r0, PTEMAXED	/* write out start point */
_zeroouttlb:
	mts	rtlbx, r3
	mts	rtlbhi, r0
	mts	rtlblo, r0
	bgtid	r3, _zeroouttlb	/* Uses delay slot */
	addik	r3, r3, -1
.end _actualstart
_setkernelpid:
	mts	rpid, r0
	nop
	bri	4		/* sync required */

	/* setup TLB0 */
	/* 1 <-> mapping for 1MB page at 0x00 */
	ori	r11, r0, 0x0000
	mts	rtlbx, r11
	ori	r4, r0, EX|WR
	mts	rtlblo, r4
	ori	r4, r0, VALID|PAGE1M 
	mts	rtlbhi, r4

	/* setup TLB1 - page table space */
	/* maps SECOND_MAP_PHYS <-> SECOND_MAP_VERT for 4k */
	ori	r11, r0, 0x01
	mts	rtlbx, r11
	ori	r4, r0, SECOND_MAP_PHYS|EX|WR
	mts	rtlblo, r4
	ori	r4, r0, SECOND_MAP_VIRT|VALID|PAGE4K
	mts	rtlbhi, r4

	/* setup TLB2 - 64K stack */
	ori	r11, r0, 0x02
	mts	rtlbx, r11
	ori	r4, r0, STACK_MAP_PHYS
	andi	r4, r4, PAGE64KMASK
	ori	r4, r4, WR
	mts	rtlblo, r4

	ori	r4, r0, STACK_MAP_VIRT
	andi	r4, r4, PAGE64KMASK
	ori	r4, r4, VALID|PAGE64K
	mts	rtlbhi, r4

	/* set stack pointer registers */
	/* we are going to place LRU queue right at the very bottom of stack */
	ori	r4, r0, STACK_MAP_VIRT
	mts	rslr, r4
	ori	r4, r0, STACK_BOTTOM
	/* one byte per LRU ref */
	rsubi	r4, r0, PTECNT - MAXPINNED
	mts	rshr, r4
	/* set r1 as stack pointer */
	addi	r4, r0, -3 
	or	r1, r0, r4
	/* order the LRU references */
	addi	r3, r0, MAXPINNED 	/* start from here */
	addi	r4, r0, PTECNT		/* max PTEs */
	addi	r5, r0, STACK_BOTTOM	/* write here */

zero_lru_stack:
	rsubi	r6, r3, MAXPINNED
	sb	r3, r5, r6
	addi	r3, r0, 1
	rsub	r6, r3, r4
	bnei	r6, zero_lru_stack
	 

turn_on_vm:
	mfs	r4, rmsr
	nop
	ori	r4, r0, VM_ON 
	mts	rmsr, r4
	nop

	/* Populate page table */
	/* Zero the memory first of all */
	ori	r11, r0, PTECNT
	ori	r12, r0, SECOND_MAP_VIRT
	ori	r19, r0, PTE_SIZE 
	ori	r20, r0, 0x00
	
outer_zero_loop:
	beqid	r11, finished_zero_loop
	addik	r11, r11, -1

inner_zero_loop:
	sw	r0, r12, r20
	addik	r20, r20, 0x04 
	rsub	r21, r20, r19
	bleid	r21, end_inner_zero_loop
	nop
	braid	inner_zero_loop
	nop

end_inner_zero_loop:
	add	r12, r12, r19
	braid	outer_zero_loop
	ori	r20, r0, 0x00	

finished_zero_loop:
	nop		

prep_ptes:
	ori	r11, r0, PTECNT
	ori	r12, r0, SECOND_MAP_VIRT 
	ori	r19, r0, PTE_SIZE
	ori	r20, r0, 0x00

/* We work on the basis we have (PTECNT - MAXPINNED) 4k frames */
/* In physical addresses from 0x500000 onwards */
/* MAXPINNED entries first */
	ori	r22, r0, MAXPINNED
copy_pinned_tlbs:
	mts	rtlbx, r20
	mfs	r21, rtlblo
	sw	r21, r12, r0
	mfs	r21, rtlbhi
	swi	r21, r12, PTE_SIZE_HALF
	add	r12, r12, r19
	addik	r22, r22, -1
	bneid	r22, copy_pinned_tlbs
	addik	r20, r20, 0x01

	addik	r11, r11, -MAXPINNED
	ori	r21, r0, FRAME_BASE|WR|EX

pte_loop:
	addik	r11, r11, -1
	beqid	r11, finished_pte_loop
	sw	r21, r12, r0
	addik	r21, r21, PAGE_SZ 
	braid	pte_loop
	add	r12, r12, r19

finished_pte_loop:
	nop

go_user_mode:
	bralid	r15, generated_traffic
	nop
.global exit
.ent exit
.type exit, @function

exit:
	nop
.end exit

_interrupt_handler:
	ori	r20, r0, 0x01
	bri	0


_hw_exception_handler:
	mfs	r3, resr
	andi	r4, r3, 0x1F
	or	r5, r0, r0
	rsub	r6, r5, r4
	beqi	r6, handle_stream_exception
	switchex
	beqi	r6, handle_unaligned_data_exception
	switchex
	beqi	r6, handle_illegal_opcode
	switchex
	beqi	r6, handle_ibus_error
	switchex
	beqi	r6, handle_dbus_error
	switchex
	beqi	r6, handle_divide_error
	switchex
	beqi	r6, handle_fp_error
	switchex
	beqi	r6, handle_priv_or_stack_error
	addi	r5, r5, 0x09
	rsub	r6, r5, r4	
	beqid	r6, handle_datastore_error
	switchex
	beqid	r6, handle_inststore_error
	switchex
	beqid	r6, handle_datatlb_miss
	switchex
	beqid	r6, handle_insttlb_miss
	nop
	/* should never get here */
	bri 0

handle_stream_exception:
handle_unaligned_data_exception:
handle_illegal_opcode:
handle_ibus_error:
handle_dbus_error:
handle_divide_error:
handle_fp_error:
handle_priv_or_stack_error:

	bri 0

handle_datastore_error:
handle_inststore_error:
	bri 0

handle_datatlb_miss:
	ori	r3, r0, CLOCK_SWEEP 
	ori	r19, r0, sweep_stacked 
	brald	r15, r19
	nop

	/* now check if PTE addresses match */
	ori	r3, r0, MAXPINNED	/* r3 is index to PTE */
	muli	r4, r3, PTE_SIZE	/* r4 points to PTE itself */
	addik	r4, r4, SECOND_MAP_PHYS + PTE_SIZE_HALF

	mfs	r5, rear	/* r5 has faulting address */
	andi	r5, r5, PAGE4KMASK

look_in_PTE:
	lw	r6, r4, r0	/* r6 has PTE data */
	andi	r6, r6, PAGE4KMASK
	rsubi	r6, r6, r5
	bneid	r6, keep_looking_in_PTE
	lw	r6, r4, r0	/* found the PTE entry so fix it up */
	ori	r6, r6, VALID|PAGE4K
	sw	r6, r4, r0
	ori	r19, r0, get_entry_for_match 
	brald	r15, r19
	nop			/* r3 now has index to stack entry */
	ori	r19, r0, mark_stack /* so push it to back of LRU queue */
	brald	r15, r19
	nop
	mfs	r3, rear
	andi	r3, r3, PAGE4KMASK
	brai	fix_up_tlb 

keep_looking_in_PTE:
	addik	r3, r3, 1
	rsubi	r6, r3, PTECNT
	beqi	r6, end_of_PTE_look
	braid	look_in_PTE
	addik	r4, r4, PTE_SIZE

end_of_PTE_look:	
	/* Now look for an empty PTE */
	ori	r19, r0, search_stacked
	brald	r15, r19
	nop /* r3 has PTE index, r4 has stack index */
	/* is it an empty entry? */
	addik	r1, r1, -4
	sw	r3, r1, r0
	addik	r1, r1, -4
	sw	r4, r1, r0
	muli	r5, r3, PTE_SIZE
	addik	r5, r5, SECOND_MAP_PHYS + PTE_SIZE_HALF
	lw	r6, r5, r0
	ori	r4, r0, PAGE_SIZE
	ori	r3, r0, DUMMY_ZONE
	beqid	r6, PTE_entry_empty
	nop

	andi	r5, r6, PAGE4KMASK
	or	r6, r0, r0
	lw	r30, r5, r6
write_out:
	sw	r30, r3, r6
	addik	r6, r6, 0x04
	rsub	r30, r6, r4
	bneid	r30, write_out
	lw	r30, r5, r6

PTE_entry_empty:
	/* now, fix up PTE entry */
	mfs	r6, rear
	andi	r6, r6, PAGE4KMASK
	ori	r6, r6, VALID|PAGE4K
	sw	r6, r5, r0

	or	r6, r0, r0
	mfs	r5, rear
	andi	r5, r5, PAGE4KMASK
	lw	r30, r3, r6

write_in:
	sw	r30, r5, r6
	addik	r6, r6, 0x04
	rsub	r30, r6, r4
	bneid	r30, write_in
	lw	r30, r3, r6

	lw	r4, r1, r0
	addik	r1, r1, 0x04

	or	r3, r4, r0
	ori	r19, r0, mark_stack
	brald	r15, r19
	nop
	lw	r3, r1, r0
	addik	r1, r1, 0x04 /* r3 indexes PTE entry */

	mfs	r4, rear
	andi	r4, r4, PAGE4KMASK

fix_up_tlb:
	/* now have fixed the PTE but have to fix the TLBs */
	/* r4 has the page we need to slot in */
	/* r3 has the index to the PTE */

	addik	r1, r1, -4
	sw	r3, r1, r0
	/* is there a free TLB slot? */
	ori	r5, r0, MAXPINNED
	ori	r6, r0, TLBCNT
loop_fix_up_tlb:
	mts	rtlbx, r5
	mfs	r3, rtlbhi
	andi	r3, r3, VALID
	bnei	r3, keep_fixing_tlb
	/* have an invalid TLB entry, so fix it up */
	lw	r3, r1, r0
	addik	r1, r1, 0x04
	muli	r3, r3, PTE_SIZE
	addik	r3, r3, SECOND_MAP_PHYS
	lw	r3, r3, r0
	andi	r3, r3, PAGE4KMASK
	ori	r3, r3, EX|WR
	mts	rtlbo, r3
	andi	r4, r4, VALID|PAGE4K
	rted	r17, 0x0
	mts	rtlbhi, r4

keep_fixing_tlb:
	addik	r5, r5, 0x01
	rsub	r3, r5, r6
	bnei	r3, loop_fix_up_tlb

/* we have invalid TLB entries - so roll the clock on */
	brai	handle_data_tlb_miss

handle_insttlb_miss:

	ori 	r19, r0, 0xDEADBEEF
	bri	0	


_handle_breakpoint:
	ori	r20, r0, 0x10
	nop
	bri 0 /*endless loop if it ever works */

_exception_handler:
	/* We are now back in real mode */
	ori	r20, r0, 0x03
	bri	0

/* if the page is mapped in the TLB we have to dump it */

/* clear_from_tlb -if tlb entry exists, mark it invalid */
/* r27 holds data */
clear_from_tlb:
	andi	r27, r27, PAGE4KMASK
	ori	r3, r0, MAXPINNED
	ori	r4, r0, TLBCNT
loop_clear_from_tlb:
	mts	rtlbx, r3
	mfs	r6, rtlbhi
	andi	r6, r6, PAGE4KMASK
	rsubi	r5, r6, r27
	bnei	r5, keep_clearing_from_tlb
	rtsd	r15, 0x08	/* found a match so wipe it */
	mts	rtlbhi, r0
keep_clearing_from_tlb:
	addik	r3, r3, 0x01
	rsubi	r5, r3, r4
	bnei	loop_clear_from_tlb
	rtsd	r15, 0x08
	nop
	

/* LRU subroutines follow */
mark_stacked:
	/* r3 has queue entry to be demoted */
	/* store r4, r5, r6 on stack */
	addik	r1, r1, -4
	sw	r4, r1, r0
	addik	r1, r1, -4
	sw	r5, r1, r0
	addik	r1, r1, -4
	sw	r6, r1, r0
	
	ori	r6, r0, PTECNT - MAXPINNED

	or	r4, r3, r0
	muli	r3, r3, ENTRY_SIZE
	rsubi	r3, r3, STACK_BOTTOM
	lbu	r3, r3, r0 /* r3 now holds contents of entry to be demoted */
marking_loop:
	rsub	r5, r4, r6
	bnei	r5, keep_on_marking
	ori	r3, r3, 0xC0
	sb	r3, r4, r0
	brai	end_the_sweep /* we are done */

keep_on_marking:
	addik	r5, r4, -1
	muli	r5, r5, ENTRY_SIZE
	rsubi	r5, r5, STACK_BOTTOM
	lbu	r5, r5, r0
	addik	r1, r1, -4
	sw	r3, r1, r0
	muli	r3, r4, ENTRY_SIZE
	rsubi	r3, r3, STACK_BOTTOM
	sb	r5, r3, r0
	lw	r3, r1, r0
	addik	r1, r1, 0x04
	addik	r4, r4, -1
	brai	marking_loop
	
/* End of marking function */	


search_stacked:
	/* r3 will return PTE number */
	/* r4 will return the LRU queue position */
	/* store r5, r6 on stack */
	addik	r1, r1, -4
	sw	r5, r1, r0
	addik	r1, r1, -4
	sw	r6, r1, r0
	
	or	r4, r0, r0	/* where we are */
test_next_on_stack:
	lbui	r5, r4, STACK_BOTTOM
	andi	r5, r5, 0x40
	beqid	r5, found_invalid_on_stack
	addik	r4, r4, -ENTRY_SIZE
	brai	test_next_on_stack

found_invalid_on_stack:
	lbui	r3, r4, STACK_BOTTOM
	andi	r3, r3, 0x3F
	lw	r6, r1, r0
	addik	r1, r1, 0x04
	lw	r5, r1, r0
	rtsd	r15, 0x08
	addik	r1, r1, 0x04	

/* end of searching fucnction */ 


/*sweep*/
sweep_stacked:
	/* r3 has number of pages to mark */
	/* store r4, r5, r6 on stack */
	addik	r1, r1, -4
	sw	r4, r1, r0
	addik	r1, r1, -4
	sw	r5, r1, r0
	addik	r1, r1, -4
	sw	r6, r1, r0
	/* first of all - do we need to do this? */
	ori	r4, r0, ENTRY_SIZE
	muli	r4, r4, PTECNT - MAXPINNED
	rsubi	r5, r4, STACK_BOTTOM
	lbu	r6, r0, r5
	andi	r6, r6, 0xC0	/* 2 highest bits */
	bneid	r6, keep_sweeping_stack
end_the_sweep:
	lw	r6, r1, r0
	addik	r1, r1, 0x04
	lw	r5, r1, r0
	addik	r1, r1, 0x04
	lw	r4, r1, r0
	rtsd	r15, 0x08	/* no, we don't so return */
	addik	r1, r1, 0x04
	

keep_sweeping_stack:	/* yes, we do */
	ori	r4, r0, PTECNT - MAXPINNED	/* total sweepable entries */
	or	r5, r0, r0			/* swept this many so far */
	lbui	r6, r5, STACK_BOTTOM
next_sweeping_stack:
	andi	r6, r6, 0x40			/* V bit only */
	bneid	r6, still_sweeping_stack
	/* clear from the TLB - if it's in there */
	addik	r1, r1, -4
	sw	r15, r1, r0
	lbui	r6, r5, STACK_BOTTOM
	addik	r1, r1, -4
	sw	r6, r1, r0
	andi	r6, r6, 0x3F
	muli	r29, r6, PTE_SIZE
	addik	r29, r6, SECOND_MAP_PHYS
	lwi	r27, r29, PTE_SIZE_HALF
	addik	r1, r1, -4
	sw	r27, r1, r0
	addik	r1, r1, -4
	sw	r29, r1, r0
	ori	r6, r0, clear_from_tlb
	brald	r15, r6
	nop
	/* fix the PTE entry too */
	lw	r29, r1, r0
	addik	r1, r1, 4
	lw	r27, r1, r0
	addik	r1, r1, 4
	andi	r27, r27, ~VALID
	sw	r27, r29, r0
	lw	r6, r1, r0
	addik	r1, r1, 4
	lw	r15, r1, r0
	addik	r1, r1, 4
	andi	r6, r6, 0xBF
	sbi	r6, r5, STACK_BOTTOM
	addi	r3, r3, -1
	beqid	r3, end_the_sweep		/* done enough */
still_sweeping_stack:
	addi	r5, r5, -0x01
	add	r6, r5, r4
	bneid	r6, end_the_sweep		/* end of the stack */
	lbui	r6, r5, STACK_BOTTOM
	brai	next_sweeping_stack

/* end of sweeping function */

/* get_entry_for_match function */

get_entry_for_match:
	/* r3 has the index for the PTE */
	/* return with r3 = stack entry that matches */
	ori	r4, r0, STACK_BOTTOM
	ori	r5, r0, r0
loop_getting:
	lbu	r6, r4, r5
	rsubi	r6, r6, r3
	bnei	r6, keep_getting
	rsubi	r5, r5, 0
	or	r3, r5, r0
	rtsd	r15, 0x08
	nop
keep_getting:
	addik	r5, r5, -1
	brai	loop_getting
	
/* end of get_entry_for_match */	
