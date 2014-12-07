IMPERAS_HOME := $(shell getpath.exe "$(IMPERAS_HOME)")
include $(IMPERAS_HOME)/bin/Makefile.include

CROSS = MICROBLAZE

ASRC = startup.S traffic.S
AEXE = $(patsubst %.S,%.$(CROSS).elf,$(ASRC))
-include $(IMPERAS_HOME)/lib/$(IMPERAS_ARCH)/CrossCompiler/$(CROSS).makefile.include
ifeq ($($(CROSS)_CC),)
    IMPERAS_ERROR := $(error "Please install the $(CROSS) toolchain")
endif

all: $(AEXE)

%.$(CROSS).elf: %.o
	echo "Linking $@"
	$(CROSS_COMPILE)ld -T ./bootlink.lds -o $@ $< 


%.o: %.S traffic.S
	echo "Compiling $<"
	$(CROSS_COMPILE)as -o $@ startup.S traffic.S

clean:
	rm -f *.elf *.o
