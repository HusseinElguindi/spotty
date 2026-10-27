#!/bin/sh
# Measures Spotty's speed, memory, CPU, energy and disk use. No sudo; writes only under .build/
# and Spotty's own Application Support folder. See docs/metrics.md for what each number means.
#
#   scripts/metrics.sh            # everything (about 3 minutes, mostly the 60 s idle sample)
#   RUNS=1 scripts/metrics.sh     # one benchmark run instead of three
#
# The benchmark shows the panel for a few seconds without taking the keyboard.
set -eu
cd "$(dirname "$0")/.."
RUNS=${RUNS:-3}
out=.build/metrics
mkdir -p "$out"

echo "== Build"
scripts/bundle.sh >/dev/null
# The benchmark hooks are DEBUG-only; build them with release optimizations.
swift build -c release -Xswiftc -DDEBUG --build-path .build/metrics-build --product Spotty >/dev/null
bench_bin="$(swift build -c release -Xswiftc -DDEBUG --build-path .build/metrics-build --show-bin-path)/Spotty"

echo "== Benchmark ($RUNS runs)"
: > "$out/bench.txt"
i=1
while [ "$i" -le "$RUNS" ]; do
    log="$out/bench-$i.log"
    SPOTTY_BENCH=1 "$bench_bin" > "$log" 2>&1 &
    pid=$!
    # Wait for the benchmark to finish its measurements, then look for leaks while it idles.
    until grep -q ready_for_leaks "$log" 2>/dev/null; do
        kill -0 "$pid" 2>/dev/null || { echo "benchmark exited early:"; cat "$log"; exit 1; }
        sleep 1
    done
    leaks "$pid" > "$out/leaks-$i.txt" 2>&1 || true
    echo "BENCH leaks_count=$(grep -Eo '[0-9]+ leaks? for' "$out/leaks-$i.txt" | grep -Eo '^[0-9]+' || echo '?')" >> "$log"
    echo "BENCH leaked_bytes=$(grep -Eo 'for [0-9]+ total leaked bytes' "$out/leaks-$i.txt" | grep -Eo '[0-9]+' || echo '?')" >> "$log"
    wait "$pid" || true
    grep '^BENCH ' "$log" | sed 's/^BENCH //' >> "$out/bench.txt"
    i=$((i + 1))
done
# Median of each key across runs.
awk -F= '{ v[$1] = v[$1] " " $2 } END { for (k in v) print k, v[k] }' "$out/bench.txt" | sort | while read -r key values; do
    median=$(printf '%s\n' $values | sort -g | awk '{ a[NR] = $1 } END { print (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2 }')
    printf '%-40s %s   (runs: %s)\n' "$key" "$median" "$(echo $values)"
done | grep -v ready_for_leaks

echo "== Idle, release app"
was_running=0
pgrep -f "build/Spotty.app/Contents/MacOS/Spotty" >/dev/null && was_running=1
osascript -e 'quit app id "com.hus.spotty"' >/dev/null 2>&1 || true
sleep 1
open build/Spotty.app
sleep 10
pid=$(pgrep -f "build/Spotty.app/Contents/MacOS/Spotty")
footprint "$pid" 2>/dev/null | awk '/phys_footprint:/ { print "idle_footprint             ", $2, $3 }'
ps -o rss= -p "$pid" | awk '{ printf "idle_rss                    %.1f MB\n", $1 / 1024 }'
# CPU from the process's own CPU time over 60 s; wakeups and power from top. top's idlew column
# is a running total, so the rate is its change over the window.
secs() { ps -o time= -p "$1" | awk -F'[:.]' '{ print ($1 * 60 + $2) + ("0." $3) }'; }
cpu_before=$(secs "$pid")
top -l 31 -s 2 -pid "$pid" -stats pid,cpu,idlew,power,threads > "$out/top-idle.txt"
cpu_after=$(secs "$pid")
awk -v pid="$pid" -v c0="$cpu_before" -v c1="$cpu_after" '
    $1 == pid { n++; w = $3 + 0; if (n == 1) w0 = w; w1 = w; if (n > 1) { power += $4; m++ }; th = $5 }
    END {
        printf "idle_cpu_percent            %.2f  (%.2f s of CPU in 60 s)\n", (c1 - c0) / 60 * 100, c1 - c0
        printf "idle_wakeups_per_s          %.2f\n", (w1 - w0) / 60
        printf "idle_power                  %.2f\n", power / m
        printf "threads                     %d\n", th
    }' "$out/top-idle.txt"
[ "$was_running" -eq 1 ] || osascript -e 'quit app id "com.hus.spotty"' >/dev/null 2>&1 || true

echo "== Disk"
du -sk build/Spotty.app | awk '{ printf "bundle                      %d KB\n", $1 }'
stat -f 'binary                      %z bytes' build/Spotty.app/Contents/MacOS/Spotty
support="$HOME/Library/Application Support/Spotty"
for f in "$support"/*; do [ -e "$f" ] && stat -f "%N %z bytes" "$f" | sed "s|$support/||"; done
