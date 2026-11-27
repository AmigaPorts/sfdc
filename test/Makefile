# Smoke test: generate the header flavours the m68k-amigaos toolchain
# asks sfdc for and check that the expected symbols come out.
#
#   make -C test [SFDC=../sfdc] [CC=m68k-amigaos-gcc]

SFDC ?= ../sfdc
FD2SFD ?= $(dir $(SFDC))fd2sfd
FD2PRAGMA ?= $(dir $(SFDC))fd2pragma
SFD = test_lib.sfd
OUT = out

# The generated code is compiled with an Amiga compiler (check-compile)
ifeq ($(origin CC),default)
CC = m68k-amigaos-gcc
endif

all: check check-headername check-fd check-compile

# The library bases for libnix's startup code to open, one per kind of name
AUTOOPEN_SFD = $(SFD) $(wildcard autoopen/*_lib.sfd)
base = '^void\* $(1)\[2\] = { (void\*)-1, "$(2)" };'

# What goes into a link library besides the bases
LIB = $(OUT)/stubs/.done $(OUT)/lvolib.s

# The headers a program includes, laid out as in an include directory
TEST_INCLUDES = \
	$(OUT)/include/proto/test.h \
	$(OUT)/include/inline/test.h \
	$(OUT)/include/clib/test_protos.h

check: $(OUT)/inline.h $(OUT)/inline_vbcc.h $(OUT)/proto.h $(OUT)/lvo.i $(OUT)/clib.h check-autoopen $(LIB)
	grep -q '^#define TestAdd(___a, ___b)' $(OUT)/inline.h
	grep -q '^#define TestLookup(___list, ___name)' $(OUT)/inline.h
	grep -q '^#define TestPrintf(' $(OUT)/inline.h
	grep -qF 'register VOID (**__v1)() __asm("a1")' $(OUT)/inline.h
	grep -q '^#define TestAdd(a, b) __TestAdd(TestBase, (a), (b))' $(OUT)/inline_vbcc.h
	# vbcc: the variable arguments' address in the register of the "...",
	# or of the last named argument when the array starts with it
	grep -qF 'LONG __TestPrintf(__reg("a6") struct Library * , __reg("a0") CONST_STRPTR format , ... ) = "\tlea\t0(a7),a1\n\tjsr\t-42(a6)";' $(OUT)/inline_vbcc.h
	grep -qF 'LONG __TestFPrintf(__reg("a6") struct Library * , __reg("d1") LONG fh , __reg("d2") CONST_STRPTR format , ... ) = "\tmove.l\td3,-(a7)\n\tmove.l\ta7,d3\n\taddq.l\t#4,d3\n\tjsr\t-66(a6)\n\tmove.l\t(a7)+,d3";' $(OUT)/inline_vbcc.h
	grep -qF 'APTR __TestNewObject(__reg("a6") struct Library * , __reg("a0") CONST_STRPTR cl , Tag tag1 , ... ) = "\tmove.l\ta2,-(a7)\n\tlea\t4(a7),a2\n\tjsr\t-72(a6)\n\tmove.l\t(a7)+,a2";' $(OUT)/inline_vbcc.h
	grep -qF 'LONG __TestDPrintf(__reg("a6") struct Library * , __reg("a0") CONST_STRPTR format , ... ) = "\tmove.l\ta7,d1\n\tjsr\t-78(a6)";' $(OUT)/inline_vbcc.h
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

# --headername: the proto and inline headers include each other under the
# caller's name, and clib/ keeps the base name
check-headername: $(OUT)/headername/proto.h $(OUT)/headername/inline.h
	grep -q '^#   include <inline/test_lib.h>' $(OUT)/headername/proto.h
	grep -q '^#  include <inline/test_lib_protos.h>' $(OUT)/headername/proto.h
	grep -q '^#include <clib/test_protos.h>' $(OUT)/headername/proto.h
	grep -q '^#include <proto/test_lib.h>' $(OUT)/headername/inline.h
	@echo "sfdc headername test passed"

$(OUT)/headername/proto.h: MODE = proto
$(OUT)/headername/inline.h: MODE = macros

$(OUT)/headername/proto.h $(OUT)/headername/inline.h: $(SFD) $(SFDC)
	mkdir -p $(dir $@)
	$(SFDC) --target=m68k-gcc-amigaos --mode=$(MODE) --headername=test_lib --output=$@ $<

# With a cross compiler, what goes into a link library also compiles:
#   make -C test check-compile CC=m68k-amigaos-gcc
check-compile: $(LIB) $(OUT)/autoopen/.done $(TEST_INCLUDES)
	for f in $(OUT)/stubs/*.c $(OUT)/autoopen/test.c $(OUT)/lvolib.s; do \
	  $(CC) -Os -Wall -Werror -D__libnix__ -c $$f -o $(OUT)/compile.o || exit 1; \
	done
	$(CC) -Os -Wall -Wextra -Werror -I$(OUT)/include -c include.c -o $(OUT)/compile.o
	$(CC) -Os -Wall -Wextra -Werror -I$(OUT)/include -c call.c -o $(OUT)/compile.o
	$(CC) -O0 -I$(OUT)/include -S include.c -o $(OUT)/include.s
	! grep -q '_va:' $(OUT)/include.s
	@echo "sfdc compile test passed"

# FD input: fd/sample_lib.fd and fd/sample_protos.h have a case of each
# rule of the conversion, fd/bad_lib.fd and fd/bad_protos.h its errors
check-fd: $(FD2SFD) $(FD2PRAGMA) $(OUT)/fd/test_lib.fd $(OUT)/fd/test_protos.h
	$(FD2SFD) fd/sample_lib.fd fd/sample_protos.h -o $(OUT)/fd/sample_lib.sfd 2>$(OUT)/fd/sample.err
	cmp fd/sample_lib.sfd $(OUT)/fd/sample_lib.sfd
	cmp fd/sample.err $(OUT)/fd/sample.err
	! $(FD2SFD) fd/bad_lib.fd fd/bad_protos.h -o $(OUT)/fd/bad_lib.sfd 2>$(OUT)/fd/bad.err
	cmp fd/bad.err $(OUT)/fd/bad.err
	test ! -e $(OUT)/fd/bad_lib.sfd
	# The FD and clib files written from an SFD file convert back to it
	$(FD2SFD) $(OUT)/fd/test_lib.fd $(OUT)/fd/test_protos.h -o $(OUT)/fd/test_lib.sfd
	$(SFDC) --quiet --target=m68k-gcc-amigaos --mode=macros $(SFD) >$(OUT)/fd/test-from-sfd.h
	$(SFDC) --quiet --target=m68k-gcc-amigaos --mode=macros $(OUT)/fd/test_lib.sfd | cmp $(OUT)/fd/test-from-sfd.h -
	# fd2pragma: both of its command lines, and its file names
	$(FD2PRAGMA) fd/sample_lib.fd CLIB fd/sample_protos.h TO $(OUT)/fd SPECIAL 40 2>/dev/null | grep -qx 'ResultFile: $(OUT)/fd/sample.h'
	$(SFDC) --quiet --target=m68k-gcc-amigaos --mode=macros $(OUT)/fd/sample_lib.sfd | cmp $(OUT)/fd/sample.h -
	$(FD2PRAGMA) -i fd/sample -s 21 -t $(OUT)/fd 2>/dev/null | grep -qx 'ResultFile: $(OUT)/fd/sample_lib.i'
	! $(FD2PRAGMA) -i fd/sample_lib.fd -s 40 -t $(OUT)/fd >/dev/null 2>&1
	! $(FD2PRAGMA) -i fd/sample_lib.fd -s 12 -t $(OUT)/fd >/dev/null 2>&1
	@echo "sfdc FD test passed"

$(OUT)/fd/test_lib.fd: MODE = fd
$(OUT)/fd/test_protos.h: MODE = clib

$(OUT)/fd/test_lib.fd $(OUT)/fd/test_protos.h: $(SFD) $(SFDC)
	mkdir -p $(dir $@)
	$(SFDC) --quiet --mode=$(MODE) --output=$@ $<

# One run for all the SFD files, which must not warn.  A gadget, image or
# datatype class gets its directory; exec.library, a device and an SFD file
# without ==libname get no entry.
check-autoopen: $(OUT)/autoopen/.done
	test ! -s $(OUT)/autoopen/.done
	grep -q $(call base,TestBase,test.library) $(OUT)/autoopen/test.c
	grep -q $(call base,MiscBase,misc.resource) $(OUT)/autoopen/misc.c
	grep -q $(call base,ButtonBase,gadgets/button.gadget) $(OUT)/autoopen/button.c
	grep -q $(call base,BevelBase,images/bevel.image) $(OUT)/autoopen/bevel.c
	grep -q $(call base,PictureBase,datatypes/picture.datatype) $(OUT)/autoopen/picture.c
	! grep -q LIB_LIST $(OUT)/autoopen/timer.c
	! grep -q LIB_LIST $(OUT)/autoopen/exec.c
	! grep -q LIB_LIST $(OUT)/autoopen/engine.c

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

$(OUT)/include/proto/test.h: MODE = proto
$(OUT)/include/inline/test.h: MODE = macros
$(OUT)/include/clib/test_protos.h: MODE = clib

$(TEST_INCLUDES): $(SFD) $(SFDC)
	mkdir -p $(dir $@)
	$(SFDC) --target=m68k-gcc-amigaos --mode=$(MODE) --output=$@ $<

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

.PHONY: all check check-autoopen check-compile check-fd check-headername clean
