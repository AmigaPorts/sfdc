# Smoke test: generate the header flavours the m68k-amigaos toolchain
# asks sfdc for and check that the expected symbols come out.
#
#   make -C test check [SFDC=../sfdc]

SFDC ?= ../sfdc
SFD = test_lib.sfd
OUT = out

all: check

# The library bases for libnix's startup code to open, one per kind of name
AUTOOPEN_SFD = $(SFD) $(wildcard autoopen/*_lib.sfd)
base = '^void\* $(1)\[2\] = { (void\*)-1, "$(2)" };'

# What goes into a link library besides the bases
LIB = $(OUT)/stubs/.done $(OUT)/lvolib.s

check: $(OUT)/inline.h $(OUT)/inline_vbcc.h $(OUT)/proto.h $(OUT)/lvo.i $(OUT)/clib.h check-autoopen $(LIB)
	grep -q '^#define TestAdd(___a, ___b)' $(OUT)/inline.h
	grep -q '^#define TestLookup(___list, ___name)' $(OUT)/inline.h
	grep -q '^#define TestPrintf(' $(OUT)/inline.h
	grep -q '^#define TestAdd(a, b) __TestAdd(TestBase, (a), (b))' $(OUT)/inline_vbcc.h
	grep -q 'TestBase' $(OUT)/proto.h
	grep -q '^#  include <inline/test_protos.h>' $(OUT)/proto.h
	grep -q '_LVOTestAdd' $(OUT)/lvo.i
	! grep -q '_LVOTestPrivate' $(OUT)/lvo.i
	grep -q 'LONG TestAdd(' $(OUT)/clib.h
	grep -q '^  return __TestAdd_base(BASE_NAME, ___a, ___b);' $(OUT)/stubs/TestAdd.c
	grep -q '^  __TestReset_base(BASE_NAME);' $(OUT)/stubs/TestReset.c
	grep -q '^#define __TestPrintfA_base(' $(OUT)/stubs/TestPrintf.c
	grep -q '^  return __TestPrintfA_base(BASE_NAME, ___format, (APTR) (&___format + 1));' $(OUT)/stubs/TestPrintf.c
	test ! -e $(OUT)/stubs/TestPrivate.c
	grep -q '^_LVOTestAdd = -30' $(OUT)/lvolib.s
	grep -q '^_LVOTestPrivate = -54' $(OUT)/lvolib.s
	@echo "sfdc smoke test passed"

# With a cross compiler, what goes into a link library also compiles:
#   make -C test check-compile CC=m68k-amigaos-gcc
check-compile: $(LIB) $(OUT)/autoopen/.done
	for f in $(OUT)/stubs/*.c $(OUT)/autoopen/test.c $(OUT)/lvolib.s; do \
	  $(CC) -Os -Wall -Werror -D__libnix__ -c $$f -o $(OUT)/compile.o || exit 1; \
	done
	@echo "sfdc compile test passed"

# One run for all the SFD files, which must not warn.  A gadget, image or
# datatype class gets its directory; exec.library and a device get no entry.
check-autoopen: $(OUT)/autoopen/.done
	test ! -s $(OUT)/autoopen/.done
	grep -q $(call base,TestBase,test.library) $(OUT)/autoopen/test.c
	grep -q $(call base,MiscBase,misc.resource) $(OUT)/autoopen/misc.c
	grep -q $(call base,ButtonBase,gadgets/button.gadget) $(OUT)/autoopen/button.c
	grep -q $(call base,BevelBase,images/bevel.image) $(OUT)/autoopen/bevel.c
	grep -q $(call base,PictureBase,datatypes/picture.datatype) $(OUT)/autoopen/picture.c
	! grep -q LIB_LIST $(OUT)/autoopen/timer.c
	! grep -q LIB_LIST $(OUT)/autoopen/exec.c

$(OUT):
	mkdir -p $(OUT)

$(OUT)/autoopen/.done: $(AUTOOPEN_SFD) $(SFDC) | $(OUT)
	rm -rf $(OUT)/autoopen && mkdir -p $(OUT)/autoopen
	$(SFDC) --quiet --target=m68k-amigaos --mode=autoopen --output=$(OUT)/autoopen/%n.c $(AUTOOPEN_SFD) 2>$@.err
	mv $@.err $@

$(OUT)/stubs/.done: $(SFD) $(SFDC) | $(OUT)
	rm -rf $(OUT)/stubs && mkdir -p $(OUT)/stubs
	$(SFDC) --target=m68k-gcc-amigaos --mode=stubs --output=$(OUT)/stubs/%f.c $<
	touch $@

$(OUT)/lvolib.s: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68k-gcc-amigaos --mode=lvolib --output=$@ $<

$(OUT)/inline.h: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68k-gcc-amigaos --mode=macros --output=$@ $<

$(OUT)/inline_vbcc.h: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68kvbcc-amigaos --mode=macros --output=$@ $<

$(OUT)/proto.h: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68k-amigaos --mode=proto --output=$@ $<

$(OUT)/lvo.i: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68k-amigaos --mode=lvo --output=$@ $<

$(OUT)/clib.h: $(SFD) $(SFDC) | $(OUT)
	$(SFDC) --target=m68k-amigaos --mode=clib --output=$@ $<

clean:
	rm -rf $(OUT)

.PHONY: all check check-autoopen check-compile clean
