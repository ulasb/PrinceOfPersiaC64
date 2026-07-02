AS      = ca65
LD      = ld65
X64     = x64sc

SRCDIR  = src
BUILDIR = build
CFG     = pop.cfg

SOURCES = $(wildcard $(SRCDIR)/*.s) $(wildcard $(SRCDIR)/data/*.s)
OBJECTS = $(patsubst $(SRCDIR)/%.s,$(BUILDIR)/%.o,$(SOURCES))

PRG     = $(BUILDIR)/pop.prg

.PHONY: all run test clean assets

all: $(PRG)

# Regenerate data tables, graphics and level binaries from ../PrinceOfPersiaPy
assets:
	python3 tools/gen_anim_data.py
	python3 tools/gen_bgdata.py
	python3 tools/copy_levels.py
	python3 tools/convert_gfx.py

ASFLAGS ?=

$(BUILDIR)/%.o: $(SRCDIR)/%.s $(SRCDIR)/pop.inc
	@mkdir -p $(dir $@)
	$(AS) -g $(ASFLAGS) -o $@ -l $(BUILDIR)/$*.lst $<

$(PRG): $(OBJECTS) $(CFG)
	$(LD) -C $(CFG) -o $@ -m $(BUILDIR)/pop.map -Ln $(BUILDIR)/pop.lbl $(OBJECTS)

run: $(PRG)
	$(X64) -autostartprgmode 1 $(PRG)

# Headless smoke test: run ~5s of emulation in warp mode, save a screenshot.
test: $(PRG)
	$(X64) -console -warp +sound -limitcycles 8000000 \
	    -exitscreenshot $(BUILDIR)/test_shot.png \
	    -autostartprgmode 1 $(PRG) > $(BUILDIR)/vice_test.log 2>&1 || true
	@test -f $(BUILDIR)/test_shot.png && echo "OK: $(BUILDIR)/test_shot.png" || \
	    (echo "FAIL: no screenshot produced"; tail -20 $(BUILDIR)/vice_test.log; exit 1)

clean:
	rm -rf $(BUILDIR)

# disk image for real hardware / emulator file browsers
d64: $(PRG)
	c1541 -format "pop c64,01" d64 $(BUILDIR)/pop.d64 -write $(PRG) "prince of persia" >/dev/null
	@echo "OK: $(BUILDIR)/pop.d64"
