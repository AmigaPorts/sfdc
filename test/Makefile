# Smoke test: generate the header flavours the m68k-amigaos toolchain
# asks sfdc for and check that the expected symbols come out.
#
#   make -C test check [SFDC=../sfdc]

SFDC ?= ../sfdc
SFD = test_lib.sfd
OUT = out

all: check

check: $(OUT)/inline.h $(OUT)/inline_vbcc.h $(OUT)/proto.h $(OUT)/lvo.i $(OUT)/clib.h
	grep -q '^#define TestAdd(___a, ___b)' $(OUT)/inline.h
	grep -q '^#define TestLookup(___list, ___name)' $(OUT)/inline.h
	grep -q '^#define TestPrintf(' $(OUT)/inline.h
	grep -q '^#define TestAdd(a, b) __TestAdd(TestBase, (a), (b))' $(OUT)/inline_vbcc.h
	grep -q 'TestBase' $(OUT)/proto.h
	grep -q '_LVOTestAdd' $(OUT)/lvo.i
	grep -q 'LONG TestAdd(' $(OUT)/clib.h
	@echo "sfdc smoke test passed"

$(OUT):
	mkdir -p $(OUT)

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

.PHONY: all check clean
