# Performance metrics

Measured on 2026-10-27 on Hussein's Mac (Apple silicon, macOS 27.0.1, Swift 6.4), with 111 apps
installed. Repeat with `scripts/metrics.sh` (about 3 minutes). Numbers marked "median" are the
median of three benchmark runs; the runs themselves are listed in the script's output.

## Method

- **Benchmark** (`SPOTTY_BENCH=1`, `Sources/Spotty/DebugBench.swift`): a DEBUG-only mode, built
  with release optimizations (`swift build -c release -Xswiftc -DDEBUG`). It times the app's own
  code paths from inside the process and reads memory with `task_info(TASK_VM_INFO)` and CPU with
  `getrusage`. It shows the panel without taking the keyboard, so it never catches anyone's typing.
  When it finishes, the script runs `leaks` against it.
- **Idle**: the real `build/Spotty.app`, freshly launched and left alone for 10 s, then watched for
  60 s with the panel closed. CPU is from the process's own CPU time (`ps`); wakeups and power
  are from `top` (its `idlew` column is a running total, so the rate is its change over the window).
- **Disk**: `du` and `stat`.
- No sudo, nothing written outside `.build/` and `~/Library/Application Support/Spotty/`.

## Results

### Indexing

| Metric | Value | Notes |
| --- | --- | --- |
| Apps found | 111 | |
| Scan with no cache | 20 ms (median) | Every Info.plist read. The OS file cache is warm, so a scan right after boot will be slower |
| Rescan with cache | 5.5 ms (median) | Mostly `stat` calls |
| Building the search index | 0.7 ms | Folding names into search keys |
| Main thread held by a rescan | 0.003 ms | The one-assignment swap; the scan itself runs in the background |
| FSEvents callback after a change | 12 ms (median) | New bundle in a watched folder until the callback |
| Change to index updated | 41 ms (median) | Callback plus rescan |
| Launch to ready | 150 ms (median) | Process start until the first index is in (runs: 139–249 ms) |

### Speed

| Metric | Value | Notes |
| --- | --- | --- |
| Ranking per keystroke | 0.041 ms (median query) | All 111 apps, 15 queries × 200 |
| Ranking, slowest query | 0.106 ms | Budget is 8 ms |
| ⌘Space to panel drawn | 0.6 ms | `show()` plus layout and draw. Excludes hotkey delivery and the window server putting it on screen (one display frame, 8–16 ms) |
| Keystroke to frame drawn | 0.8 ms median, 2.7 ms p95 | Model, ranking, SwiftUI update, resize, layout and draw. Same exclusions |

### Memory

| State | Physical footprint | RSS |
| --- | --- | --- |
| Idle after launch | 22 MB | 94 MB |
| Panel open | 27 MB | 101 MB |
| After 200 open/type/close cycles | 37 MB | 116 MB |
| Icon cache warm (rows shown for a–z) | 37 MB | 124 MB |

Physical footprint is what Activity Monitor's Memory column shows. RSS is much larger because it
counts shared system framework pages (AppKit, SwiftUI) that every app maps.

**Leaks:** `leaks` reports 415 leaks, 19.4 KB, the same in every run. All of them are cycles inside
system XPC connections (`NSXPCConnection`, `xpc_connection_t` and the arrays and sets they hold),
with no Spotty types among them, so they come from Apple frameworks, not from Spotty's code.

### CPU and energy

| Metric | Value |
| --- | --- |
| Idle CPU, panel closed | 0.03 % (0.02 s of CPU in 60 s) |
| Idle wakeups | 0.07 per second |
| Idle power (top) | 0.02 |
| Threads at idle | 3 to 10 (system worker threads come and go) |
| Typing burst, 280 keystrokes back to back | 1.1 ms of CPU per keystroke. One core is busy only while keys arrive faster than people type |

### Disk

| Item | Size |
| --- | --- |
| `build/Spotty.app` | 1.0 MB (the binary is all of it) |
| `usage.json` | 1.8 KB |
| `usage.json.bak` | 1.8 KB |
| Writes | About 3.6 KB per save (the new file plus copying the old one to `.bak`). A launch from the panel saves 2 s later; app switches are gathered into at most one save a minute, and flushed on quit, sleep and log out |

## Read

Nothing is high. Idle cost is effectively zero, and every interactive path is well under one
display frame. Memory grows from 22 to 37 MB over the first few hundred uses (SwiftUI's caches and
app icons) and then levels off. The one variable number is launch to ready (139–249 ms), which
depends on how warm the file cache is.
