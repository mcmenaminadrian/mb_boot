/* Get here with r23 holding page address and r20 index to PTE */
/* We know there is no valid TLB entry that matches */
/* We are not writing OS code so no need to get fancy */
load_TLB:
	/* Look through the TLB entries for an invalid entry */
	addik	r3, r0, 2
scantlb:
	mts	rtlbx, r3
	
