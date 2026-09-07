/*
 * archenemy - flux-wall: testy jednostkowe funkcji czystych (bez Waylanda/EGL).
 * Budowane przez `make test`: main.c wchodzi z main() przemianowanym na
 * flux_wall_main, więc tu jest własny main().
 */
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

struct palette { float bg[3], ink[3], accent[3]; };
bool  parse_hex_color(const char *hex, float out[3]);
bool  parse_palette(const char *spec, struct palette *p);
float battery_detail(const char *power_supply_dir);

static int failures = 0;
#define CHECK(cond, msg) do { if (cond) printf("  ok   %s\n", msg); \
                              else { printf("  FAIL %s\n", msg); failures++; } } while (0)

static bool near(float a, float b) { return a - b < 0.002f && b - a < 0.002f; }

static void write_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(1); }
    fputs(content, f);
    fclose(f);
}

int main(void) {
    float c[3];
    printf("parse_hex_color\n");
    CHECK(parse_hex_color("0F1A24", c) && near(c[0], 15/255.f) && near(c[1], 26/255.f) && near(c[2], 36/255.f), "0F1A24 bez #");
    CHECK(parse_hex_color("#D8E6EE", c) && near(c[0], 216/255.f) && near(c[2], 238/255.f), "#D8E6EE z #");
    CHECK(parse_hex_color("#d8e6ee", c) && near(c[0], 216/255.f), "małe litery");
    CHECK(!parse_hex_color("D8E6E", c),  "za krótki → odrzucony");
    CHECK(!parse_hex_color("D8E6EEFF", c), "z alfą (8 znaków) → odrzucony");
    CHECK(!parse_hex_color("GGGGGG", c), "nie-hex → odrzucony");
    CHECK(!parse_hex_color(NULL, c),     "NULL → odrzucony");

    struct palette p;
    printf("parse_palette\n");
    CHECK(parse_palette("0F1A24,5C87A3,D8E6EE", &p) && near(p.ink[0], 92/255.f) && near(p.accent[1], 230/255.f), "trzy hexy");
    CHECK(parse_palette("#0F1A24,#5C87A3,#D8E6EE", &p), "trzy hexy z #");
    CHECK(!parse_palette("0F1A24,5C87A3", &p), "dwa hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,5C87A3,D8E6EE,000000", &p), "cztery hexy → odrzucone");
    CHECK(!parse_palette("0F1A24,zzzzzz,D8E6EE", &p), "śmieć w środku → odrzucony");
    CHECK(!parse_palette("", &p), "pusty → odrzucony");

    /* Atrapa /sys/class/power_supply */
    char dir[] = "/tmp/flux-wall-test-XXXXXX";
    if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
    char path[512];
    printf("battery_detail (atrapa: %s)\n", dir);

    CHECK(near(battery_detail(dir), 1.0f), "brak baterii → 1.0");

    snprintf(path, sizeof path, "%s/BAT0", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "42\n");
    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.42f), "42% na baterii → 0.42");

    snprintf(path, sizeof path, "%s/BAT0/status", dir);   write_file(path, "Charging\n");
    CHECK(near(battery_detail(dir), 1.0f), "42% ale ładuje → 1.0 (zasilanie sieciowe)");

    write_file(path, "Full\n");
    CHECK(near(battery_detail(dir), 1.0f), "Full → 1.0");

    write_file(path, "Discharging\n");
    snprintf(path, sizeof path, "%s/BAT0/capacity", dir); write_file(path, "117\n");
    CHECK(near(battery_detail(dir), 1.0f), "capacity > 100 → przycięte do 1.0");

    write_file(path, "abc\n");
    CHECK(near(battery_detail(dir), 1.0f), "śmieć w capacity → pominięte → 1.0");

    /* BAT0 bez sensu, BAT1 sensowna — ma wziąć BAT1 */
    snprintf(path, sizeof path, "%s/BAT1", dir); mkdir(path, 0755);
    snprintf(path, sizeof path, "%s/BAT1/capacity", dir); write_file(path, "7\n");
    snprintf(path, sizeof path, "%s/BAT1/status", dir);   write_file(path, "Discharging\n");
    CHECK(near(battery_detail(dir), 0.07f), "BAT0 uszkodzona, BAT1 7% → 0.07");

    /* sprzątanie */
    const char *files[] = { "BAT0/capacity", "BAT0/status", "BAT1/capacity", "BAT1/status", "BAT0", "BAT1", NULL };
    for (int i = 0; files[i]; i++) { snprintf(path, sizeof path, "%s/%s", dir, files[i]); remove(path); }
    rmdir(dir);

    printf("%s: %d błędów\n", failures ? "WYNIK" : "WSZYSTKO OK", failures);
    return failures ? 1 : 0;
}
