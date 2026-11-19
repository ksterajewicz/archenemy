# Test timing

`ARCHENEMY_TEST_TIME_SCALE` controls harness watchdogs and readiness deadlines.
It defaults to **1**. Set a finite value between **1 and 10**, inclusive; invalid
values stop the suite with exit code 2 before fixtures start. The value is chosen
explicitly, never inferred from a load average or changed during a run.

```sh
ARCHENEMY_TEST_TIME_SCALE=2 nice -n 19 bash tests/bluetooth.sh
```

`lib/timing.sh` and `lib/test_timing.py` share the same validation. Bash uses
`test_timeout <base seconds> <command...>`; Python uses `seconds(base)` for
subprocess watchdogs. `wait_until` and `Lines.receive` use monotonic deadlines.
`Lines` bounds the wait for a **complete line**, including a partial line or
multiple lines already buffered in the harness. File waits bypass PATH mocks
of `sleep`.

The doctor, Bluetooth, monitor settings, shell settings, appbinds menu and
bars/dither suites use these helpers, and so do the later platform suites:
`doctor-platforms.sh` (run limit 10 × S; the doctor **<5 s** contract
unscaled), `gaming-diag.sh` (30 × S per run; the 8-second bound of a run with
one hung source and its 1-second `ARCHENEMY_QUERY_TIMEOUT` unscaled, since a
larger bound would no longer tell a working query limit from the 30-second
hang fixture), `runtime-platforms.sh` (mouse settings 15 × S, orphan guard
20 × S) and `shell-platforms.sh` (shell settings 15 × S). Python imports of
`test_timing` do not write `__pycache__` (`lib/timing.sh` exports
`PYTHONDONTWRITEBYTECODE=1`; isolated suites would report it as a write
outside their tree). The renderer arguments, resolutions,
simulated duration, frame rate and image assertions remain unchanged. Bars has
a 600-second watchdog per render; dither has 120 seconds per render. These are
harness safeguards, not performance promises. A shorter enclosing suite limit
can still stop the whole suite first.

`run-all.sh` defaults to `ceil(600 * scale)` seconds per suite. An explicit
`RUN_ALL_TIMEOUT` is the final integer number of seconds, without multiplication;
`0` disables that deadline. A supervisor marks an actual suite deadline expiry
and sends TERM to its process group, followed by KILL after up to 10 seconds.
A suite's own exit codes 124/137 do not identify that deadline. Interruptions
still stop the runner with code 130. Processes that create their own sessions
are outside the supervisor's process group.

On failure, the runner prints the exit code and the last 200 lines, and retains
**all** stdout/stderr in a private `/tmp/archenemy-run-all-*` directory. It prints
the `.log` and `.rc` paths. Successful runs remove this directory. Shell suites
also retain a fixture-local watchdog failure marker so assertions on partial
output cannot silently pass after their harness timeout.

Product timing contracts are not multiplied: doctor **<5 s**, Bluetooth render
**<1 s**, debounce **0.3 s**, reconnect **5 s**, and the monitor confirmation
**15 s**. Timing assertions say `KONTRAKT`; harness expiry says
`ZABEZPIECZENIE`. Contract failures remain failures under load. The Bluetooth
reconnect test retains its existing 4.5-second lower tolerance, and the burst
test retains its existing render-count and observation bounds; these checks do
not prove exact scheduling at 0.3 or 5 seconds.

The doctor's own supervisor (`scripts/archenemy-doctor.sh`) counts its 4.5 s
from the moment after the Python interpreter has started and imported its
modules; the suites' **<5 s** clock also covers `bash` and interpreter start.
A run of 6.4 s with `--full` and a hung `rpm` (D8–D10 review, under
`nice -n 19` with load 1.4–4) still ended with the complete report and no
`collection deadline exceeded`, so the collector stayed within budget and the
extra time was CPU starvation before the supervisor started (a calm start
takes about 0.05 s). Such a contract failure stays a failure; its message
shows the children's CPU time and whether the supervisor fired, which tells
starvation (little CPU, supervisor not fired) from a slow collector.
`doctor-platforms.sh` runs that exact case (`--full`, hung `rpm`).

Monitor HUP tests keep stdin open until the confirmation prompt, send HUP and
require code 129 plus rollback. EOF cannot satisfy that scenario. The delayed
shell-key fixture waits for its input prompt before sending Ctrl+X, keeps its
unscaled 0.5-second gap and then sends Ctrl+Y and Enter.

`run-all-timeout.sh` tests the runner on copied fixture suites, including raw
Python exceptions, full retained logs, timeout provenance, explicit overrides,
scale validation, buffered/partial lines and signal cleanup. It never invokes
the real full suite collection.
