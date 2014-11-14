CROSS = MICROBLAZE

ASRC = startup.S
AEXE = $(patsubst %.S,%.$(CROSS).elf,$(ASRC))

all: $(AEXE)

%.$(CROSS).elf: %.o
	echo "Linking $@"
	$(CROSS_COMPILE)ld -T ./bootlink.s -o $@ $< 

%.o: %.S
	echo "Compiling $<"
	$(CROSS_COMPILE)as -o $@ $<

clean:
	- rm -f *.elf *.o
