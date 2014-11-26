/* Get here with r23 holding page address and r20 index to PTE */
/* While r21 points to high mapping */
/* We know there is no valid TLB entry that matches */
/* We are not writing OS code so no need to get fancy */
load_TLB:
	/* Look through the TLB entries for an invalid entry */
	addik	r3, r0, 2
scantlb:
	mts	rtlbx, r3
	mfs	r24, tlbhi
	andi	r25, r24, VALID
	beqi	r25, found_invalid_tlb
	addik	r3, r0, 1
	rsubi	r25, r3, TLBCNT
	beqi	r25, no_invalid_tlb
	brai	scantlb

found_invalid_tlb:
	/* set up tlblo first */
	muli	r24, r20, PAGE_SZ
	addi	r24, r24, VIRT_BASE
	ori	r24, r24, EX|WR
	mts	rtlblo, r24
	andi	r23, r23, PAGE4KMASK
	ori	r23, r23, VALID|PAGE4K
	mts	rtlbhi, r23
	rted	r17, 0x04
	nop
	
	
	
