# =============================================
#   archenemy - flux-wall
#   Budowanie klienta tapety-shadera. Kod protokołów generuje wayland-scanner
#   z XML-i dołączonych do repo (protocols/, licencja MIT) — bez zależności od
#   pakietów wayland-protocols / wlr-protocols.
#
#   make            zbuduj build/flux-wall
#   make test       testy jednostkowe części bez Waylanda (paleta, bateria, #pragma flux, DSP audio)
#   make tools      build/offscreen — klatki animacji do PNG bez ekranu (narzędzie dev)
#   make clean
# =============================================

CC      ?= gcc
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
PKGS     = wayland-client wayland-egl egl glesv2 libpulse-simple
CFLAGS  += $(shell pkg-config --cflags $(PKGS))
LDLIBS  += $(shell pkg-config --libs $(PKGS))

BUILD    = build
PROTO    = protocols
SCANNER ?= wayland-scanner

PROTO_XML  = $(PROTO)/wlr-layer-shell-unstable-v1.xml $(PROTO)/xdg-shell.xml $(PROTO)/fractional-scale-v1.xml $(PROTO)/viewporter.xml
PROTO_C    = $(BUILD)/wlr-layer-shell-unstable-v1-protocol.c $(BUILD)/xdg-shell-protocol.c $(BUILD)/fractional-scale-v1-protocol.c $(BUILD)/viewporter-protocol.c
PROTO_H    = $(BUILD)/wlr-layer-shell-unstable-v1-client-protocol.h $(BUILD)/xdg-shell-client-protocol.h $(BUILD)/fractional-scale-v1-client-protocol.h $(BUILD)/viewporter-client-protocol.h

all: $(BUILD)/flux-wall

$(BUILD):
	mkdir -p $(BUILD)

# layer-shell odwołuje się do xdg_popup, więc kod xdg-shell musi być zlinkowany.
$(BUILD)/%-protocol.c: $(PROTO)/%.xml | $(BUILD)
	$(SCANNER) private-code $< $@

$(BUILD)/%-client-protocol.h: $(PROTO)/%.xml | $(BUILD)
	$(SCANNER) client-header $< $@

# engine.c = rysowanie (GLES, bez Waylanda); main.c = Wayland/EGL i pętla.
# audio.c = analiza dźwięku z monitora wyjścia (libpulse-simple + pthread).
# util.h = zegar monotoniczny i odczyt pliku (static inline, wspólne z tools/).
$(BUILD)/flux-wall: main.c engine.c engine.h audio.c audio.h util.h $(PROTO_C) $(PROTO_H) | $(BUILD)
	$(CC) $(CFLAGS) -I$(BUILD) -o $@ main.c engine.c audio.c $(PROTO_C) $(LDLIBS) -lm -lpthread

# Testy funkcji czystych (paleta, bateria) bez Waylanda/EGL — patrz test.c.
# main.c kompilowany OSOBNO z main() przemianowanym na flux_wall_main; test.c
# ma własny main(). Jedna komenda z -Dmain dla obu plików przemianowałaby oba.
$(BUILD)/main-under-test.o: main.c engine.h audio.h util.h $(PROTO_H) | $(BUILD)
	$(CC) $(CFLAGS) -I$(BUILD) -Dmain=flux_wall_main -c -o $@ main.c

$(BUILD)/flux-wall-test: test.c engine.c engine.h audio.c audio.h util.h $(BUILD)/main-under-test.o $(PROTO_C) | $(BUILD)
	$(CC) $(CFLAGS) -I$(BUILD) -o $@ test.c engine.c audio.c $(BUILD)/main-under-test.o $(PROTO_C) $(LDLIBS) -lm -lpthread

test: $(BUILD)/flux-wall-test
	./$(BUILD)/flux-wall-test

# Narzędzie deweloperskie (NIE budowane przez install.sh): klatki animacji do
# PNG bez ekranu — EGL surfaceless + ten sam engine.c. `make tools`.
$(BUILD)/offscreen: tools/offscreen.c engine.c engine.h audio.c audio.h util.h | $(BUILD)
	$(CC) $(CFLAGS) -o $@ tools/offscreen.c engine.c audio.c $(shell pkg-config --libs egl glesv2 libpulse-simple) -lz -lm -lpthread

tools: $(BUILD)/offscreen

clean:
	rm -rf $(BUILD)

.PHONY: all test tools clean
