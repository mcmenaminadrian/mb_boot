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
	.set ENTRY_SIZE	0x01

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
	/* ignoring pinned PTEs */
	ori	r20, r0, MAXPINNED
	/* real mode into page table TAG */
	muli	r21, r20, PTE_SIZE
	addik	r21, r21, SECOND_MAP_PHYS + PTE_SIZE_HALF

	or	r26, r0, r0	/* will store first invalid PTE index */
	mfs	r24, rear
	andi	r24, r24, PAGE4KMASK	/* always 4k pages */

load_PTE:
	lw	r22, r21, r0		/* load page tag */
	bnei	r22, keep_loading_PTE
	braid	check_free_ptes
	or	r26, r0, r20

keep_loading_PTE:
	andi	r23, r22, PAGE4KMASK
	rsub	r27, r23, r24
	beqid	r27, validate_PTE
	andi	r25, r22, VALID
	addk	r25, r25, r26
	bnei	r25, next_PTE
	or	r26, r0, r20

check_free_ptes:
	lwi	r19, r0, PTEMAXED
	andi	r29, r19, 0xFFFF0000
	bnei	r29, next_PTE
	rsubi	r29, r26, TLBCNT - 1 /* have to start removal when TLB blocked */
	bnei	r29, next_PTE
	ori	r19, r19, 0xFFFF0000
	swi	r19, r0, PTEMAXED

next_PTE:
	addi	r20, r20, 0x01
	rsubi	r27, r20, PTECNT
	beqi	r27, no_PTE_match
	braid	load_PTE
	addi	r21, r21, PTE_SIZE

	/* similar code to load_PTE except now we are looking for 	*/
	/* an invalid entry we can fill in				*/

no_PTE_match:
	or	r20, r26, r26
	muli	r21, r20, PTE_SIZE
	addik	r21, r21, SECOND_MAP_PHYS + PTE_SIZE_HALF

found_invalid_PTE:
	or	r23, r24, r0
	ori	r4, r0, PAGE_SIZE
	ori	r3, r0, DUMMY_ZONE
	/* First: is the PTE entry NULL */
	beqid	r22, empty_PTE_entry
	/* No, so copy addresses */
	or	r5, r22, r0 
	or	r6, r0, r0

	lw	r30, r5, r6
copy_out:
	sw	r30, r3, r6
	addi	r6, r6, 0x04
	rsub	r30, r6, r4
	bneid	r30, copy_out
	lw	r30, r5, r6
 
empty_PTE_entry:
	/* insert the mapping in the PTE */
	/* r21 has the address we want to write to */
	/* make the mapping valid and correct size*/
	ori	r19, r23, VALID|PAGE4K
	sw	r19, r21, r0
	/* now have to copy in */
	or	r5, r23, r0
	or	r6, r0, r0

	lw	r30, r3, r6
copy_in:
	sw	r30, r5, r6
	addi	r6, r6, 0x04
	rsub	r30, r6, r4
	bneid	r30, copy_in
	lw	r30, r3, r6

	brai	load_TLB

validate_PTE:
	bnei	r25, load_TLB	/* r25 tested for VALID in delay slot */
	ori	r22, r22, VALID|PAGE4K
	sw	r22, r21, r0
	brai	load_TLB

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

/* Get here with r23 holding page address and r20 index to PTE */
/* While r21 points to high mapping */
/* We know there is no valid TLB entry that matches */
/* We are not writing OS code so no need to get fancy */
load_TLB:
	/* Look through the TLB entries for an invalid entry */
	addik	r3, r0, MAXPINNED
scantlb:
	mts	rtlbx, r3
	mfs	r24, rtlbhi
	andi	r25, r24, VALID
	beqi	r25, found_invalid_tlb
	addik	r3, r3, 1
	rsubi	r25, r3, TLBCNT
	beqi	r25, no_invalid_tlb
	bri	scantlb

found_invalid_tlb:
	/* set up tlblo first */
	muli	r24, r20, PTE_SIZE
	addi	r24, r24, SECOND_MAP_PHYS
	lw	r25, r0, r24
	andi	r25, r25, PAGE4KMASK
	ori	r25, r25, EX|WR
	mts	rtlblo, r25
	andi	r23, r23, PAGE4KMASK
	ori	r23, r23, VALID|PAGE4K
	mts	rtlbhi, r23
	rted	r17, 0x0
	nop

no_invalid_tlb:
	/* Keep on umapping pages till we hit one in the TLB */
	/* But start ahead of current PTE */
	lwi	r25, r0, PTEMAXED
	rsub	r28, r25, r20
	bnei	r28, keep_trying_tlb
	addik	r25, r25, 0x01
	rsubi	r28, r25, PTECNT
	bnei	r28, store_updated_tlbcounter
	ori	r25, r0, MAXPINNED

store_updated_tlbcounter:
	swi	r25, r0, PTEMAXED

keep_trying_tlb:
	addik	r1, r1, -4
	sw	r20, r1, r0
	brlid	r15, wipe_tlb_entry
	nop
	lw	r20, r1, r0
	addik	r1, r1, 0x04
	brai	load_TLB

/* find a TLB entry to clean */
wipe_tlb_entry:
	lwi	r25, r0, PTEMAXED
	andi	r25, r25, 0xFFFF
	/* dump TLB values on the stack */
	ori	r26, r0, TLBCNT - 1

dump_tlb_on_stack:
	mts	rtlbx, r26
	mfs	r27, rtlbhi
	andi	r27, r27, PAGE4KMASK
	addik	r1, r1, -4
	sw	r27, r1, r0
	addik	r26, r26, -1
	rsubi	r27, r26, MAXPINNED - 1
	bnei	r27, dump_tlb_on_stack
	
get_any_tlb_match:
	muli	r29, r25, PTE_SIZE
	addik	r29, r29, SECOND_MAP_PHYS

look_inside_pte:
	lwi	r27, r29, PTE_SIZE_HALF
	andi	r28, r27, VALID
	beqi	r28, try_next_pte
	andi	r27, r27, PAGE4KMASK
	or	r28, r0, r0
	ori	r26, r0, MAXPINNED - 1	

compare_to_stacked_tlb:
	addik	r26, r26, 0x01
	rsubi	r4, r26, TLBCNT
	beqi	r4, back_on_stack
	lw	r29, r1, r0
	rsub	r30, r29, r27
	bnei	r30, get_next_stacked_tlb
	or	r28, r0, r26

get_next_stacked_tlb:
	brid compare_to_stacked_tlb
	addik	r1, r1, 0x04

back_on_stack:
	ori	r26, r0, MAXPINNED

stacking_down:
	addik	r1, r1, -4
	addik	r26, r26, 0x01
	rsubi	r27, r26, TLBCNT
	bnei	r27, stacking_down

	beqi	r28, try_next_pte
	mts	rtlbx, r28
	mts	rtlbhi, r0
	muli	r29, r25, PTE_SIZE
	addik	r29, r29, SECOND_MAP_PHYS
	lwi	r27, r29, PTE_SIZE_HALF
	andi	r27, r27, ~VALID
	swi	r27, r29, PTE_SIZE_HALF
	ori	r26, r0, MAXPINNED

stacking_up:
	addik	r1, r1, 0x04
	addik	r26, r26, 0x01
	rsubi	r27, r26, TLBCNT
	bnei	r27, stacking_up
	rtsd	r15, 0x08
	nop	

try_next_pte:
	addik	r25, r25, 0x01
	rsubi	r27, r25, PTECNT
	bnei	r27, get_any_tlb_match
	brid	get_any_tlb_match
	ori	r25, r0, MAXPINNED
	
/* if the page is mapped in the TLB we have to dump it */

clear_from_tlb:
	addik	r1, r1, -4
	sw	r25, r1, r0
	ori	r20, r0, MAXPINNED
	ori	r21, r0, TLBCNT
clearing_tlb:
	mts	rtlbx, r20
	mfs	r22, rtlbhi
	andi	r23, r27, PAGE4KMASK
	andi	r25, r22, PAGE4KMASK
	rsub	r24, r25, r23
	bnei	r24, move_to_next_tlb
	andi	r22, r22, ~VALID
	lw	r25, r1, r0
	addik	r1, r1, 0x04
	rtsd	r15, 0x08
	mts	rtlbhi, r22

move_to_next_tlb:
	addik	r20, r20, 0x01
	rsub	r22, r20, r21
	bnei	r22, clearing_tlb
	lw	r25, r1, r0	
	rtsd	r15, 0x08
	addik	r1, r1, 0x04

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
	lb	r3, r3, r0 /* r3 now holds contents of entry to be demoted */
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
	lb	r5, r5, r0
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
	/* store r4, r5, r6 on stack */
	addik	r1, r1, -4
	sw	r5, r1, r0
	addik	r1, r1, -4
	sw	r6, r1, r0
	
	ori	r4, r0, r0	/* where we are */
test_next_on_stack
	lbi	r5, r4, STACK_BOTTOM
	andi	r5, r5, 0x40
	beqid	r5, found_invalid_on_stack
	addik	r4, r4, -ENTRY_SIZE
	brai	test_next_on_stack

found_invalid_on_stack:
	lbi	r3, r4, STACK_BOTTOM
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
	lb	r6, r0, r5
	andi	r6, r6, 0xC0	/* 2 highest bits */
	bneid	r6, keep_sweeping_stack
end_the sweep:
	lw	r6, r1, r0
	addik	r1, r1, 0x04
	lw	r5, r1, r0
	addik	r1, r1, 0x04
	lw	r4, r1, r0
	rtsd	r15, 0x08	/* no, we don't so return */
	addik	r1, r1, 0x04
	

keep_sweeping_stack:	/* yes, we do */
	ori	r4, r0, PTECNT - MAXPINNED	/* total sweepable entries */
	ori	r5, r0, r0			/* swept this many so far */
	lbi	r6, r5, STACK_BOTTOM
next_sweeping_stack:
	andi	r6, r6, 0x40			/* V bit only */
	bneid	r6, next_sweep_stack
	/* clear from the TLB - if it's in there */
	addik	r1, r1, -4
	sw	r15, r1, r0
	lbi	r6, r5, STACK_BOTTOM
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

	addi	r5, r5, -0x01
	add	r6, r5, r4
	bneqid	r6, end_the_sweep		/* end of the stack */
	lbi	r6, r5, STACK_BOTTOM
	brai	next_sweeping_stack

/* end of sweeping function */
