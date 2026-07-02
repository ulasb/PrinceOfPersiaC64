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

# Regenerate data tables and level binaries from ../PrinceOfPersiaPy
assets:
	python3 tools/gen_anim_data.py
	python3 tools/copy_levels.py

all: $(PRG)

$(BUILDIR)/%.o: $(SRCDIR)/%.s
	@mkdir -p $(dir $@)
	$(AS) -g -o $@ -l $(BUILDIR)/$*.lst $<

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
