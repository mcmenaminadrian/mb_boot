/* 	Microblaze start up code
	Copyright Adrian McMenamin <acm538@york.ac.uk>, 2014
	Licensed under GPL v3
*/

.section .head.text

	mts rmsr r0
	addi r8, r0 0xFFFFFFFF
	mts rmsr r8
