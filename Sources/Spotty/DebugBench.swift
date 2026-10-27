#if DEBUG
import AppKit
import Darwin
import LauncherCore

/// Development aid: `SPOTTY_BENCH=1` measures indexing, ranking, the panel, memory and CPU from
/// inside the app, prints `BENCH key=value` lines, waits 20 s for `leaks` to look, then quits.
/// Build it optimized for real numbers: `swift build -c release -Xswiftc -DDEBUG`.
/// The panel never takes the keyboard here, so a benchmark can't catch anyone's typing.
@MainActor
enum DebugBench {
    static func runIfAsked(_ app: AppDelegate) {
        guard ProcessInfo.processInfo.environment["SPOTTY_BENCH"] != nil else { return }
        app.panel?.takesKey = false
        Task { await run(app) }
    }

    private static func out(_ key: String, _ value: Double, _ digits: Int = 2) {
        print("BENCH \(key)=\(String(format: "%.\(digits)f", value))")
        fflush(stdout)
    }

    private static func ms(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? 0 : s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    /// Physical footprint and resident size in MB, as Activity Monitor's Memory column counts them.
    private static func memory() -> (footprint: Double, resident: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (-1, -1) }
        return (Double(info.phys_footprint) / 1_048_576, Double(info.resident_size) / 1_048_576)
    }

    /// User plus system CPU seconds used by this process so far.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func s(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
        return s(usage.ru_utime) + s(usage.ru_stime)
    }

    /// Seconds since this process started.
    private static func uptime() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_starttime
        return Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }

    private static func memoryReport(_ label: String) {
        let m = memory()
        out("memory_\(label)_footprint_mb", m.footprint)
        out("memory_\(label)_rss_mb", m.resident)
    }

    private static func run(_ app: AppDelegate) async {
        guard let panel = app.panel, let view = panel.panel.contentView else { return }

        // Launch to ready: process start until the first index is in.
        while app.model.index.scan.apps.isEmpty { await sleep(0.001) }
        out("launch_to_ready_ms", uptime() * 1000, 0)
        await sleep(1)
        memoryReport("idle_after_launch")

        // Indexing, off the main thread in the app; timed directly here.
        let scanner = AppScanner.standard()
        var cold: [Double] = [], warm: [Double] = [], build: [Double] = [], swap: [Double] = []
        var scan = AppScan.empty
        for _ in 0..<5 { cold.append(ms { scan = scanner.scan() }) }
        for _ in 0..<5 { warm.append(ms { scan = scanner.scan(previous: scan) }) }
        var index = AppIndex.empty
        for _ in 0..<5 { build.append(ms { index = AppIndex(scan: scan, aliases: Aliases.load()) }) }
        // The only main-thread part of a rescan: swapping the index in, which also refreshes the tray.
        for _ in 0..<5 { swap.append(ms { app.model.index = index }) }
        out("apps_found", Double(scan.apps.count), 0)
        out("scan_cold_ms", median(cold))
        out("scan_warm_ms", median(warm))
        out("index_build_ms", median(build))
        out("main_thread_swap_ms", median(swap), 3)

        // FSEvents: create a bundle in a watched temporary folder, time until the callback,
        // then add the rescan to get change-to-index.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("spotty-bench-\(getpid())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let watcher = FolderWatcher()
        var fired: UInt64 = 0
        watcher.onChange = { fired = DispatchTime.now().uptimeNanoseconds }
        watcher.start([folder.path])
        await sleep(1.5)
        var callback: [Double] = [], toIndex: [Double] = []
        for i in 0..<5 {
            fired = 0
            let start = DispatchTime.now().uptimeNanoseconds
            let contents = folder.appendingPathComponent("Bench\(i).app/Contents")
            try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = try? PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "bench.\(i)"], format: .xml, options: 0)
            try? plist?.write(to: contents.appendingPathComponent("Info.plist"))
            while fired == 0, DispatchTime.now().uptimeNanoseconds - start < 5_000_000_000 { await sleep(0.005) }
            let wait = Double(fired - start) / 1e6
            let rescan = ms { _ = AppScanner(roots: scanner.roots + [folder], bundles: scanner.bundles).scan(previous: scan) }
            callback.append(wait)
            toIndex.append(wait + rescan)
            await sleep(1.2)
        }
        watcher.stop()
        try? FileManager.default.removeItem(at: folder)
        out("fsevents_callback_ms", median(callback), 0)
        out("change_to_index_ms", median(toIndex), 0)

        // Ranking against the real index, per keystroke.
        let items = app.model.index.searchables
        let queries = ["s", "sa", "saf", "safa", "safar", "safari", "v", "vs", "vsc", "c", "co", "cod", "code", "sys pre", "zzz"]
        var rank: [Double] = []
        for q in queries {
            let keys = QueryKeys(q)
            let t = ms { for _ in 0..<200 { _ = Ranker.rank(keys, items, usage: app.model.usage, now: .now) } }
            rank.append(t / 200)
        }
        out("rank_per_keystroke_ms", median(rank), 3)
        out("rank_worst_query_ms", rank.max() ?? 0, 3)

        // Hotkey to panel drawn: show() plus the layout and draw it triggers.
        var open: [Double] = []
        for _ in 0..<10 {
            open.append(ms { app.showPanel(); view.layoutSubtreeIfNeeded(); view.displayIfNeeded() })
            panel.hide()
            await sleep(0.1)
        }
        out("hotkey_to_panel_drawn_ms", median(open))

        // Keystroke to drawn frame: model, ranking, SwiftUI update, resize, layout and draw.
        app.showPanel()
        memoryReport("panel_open")
        var key: [Double] = []
        let cpuBefore = cpuSeconds(), wallBefore = Date()
        for _ in 0..<10 {
            app.model.query = ""
            for c in "visual studio code" {
                key.append(ms { app.model.query.append(c); view.layoutSubtreeIfNeeded(); view.displayIfNeeded() })
            }
            for c in "1299*1.13+" {
                key.append(ms { app.model.query.append(c); view.layoutSubtreeIfNeeded(); view.displayIfNeeded() })
            }
        }
        let busy = cpuSeconds() - cpuBefore, wall = Date().timeIntervalSince(wallBefore)
        out("keystroke_to_frame_ms", median(key))
        out("keystroke_to_frame_p95_ms", key.sorted()[key.count * 95 / 100])
        out("typing_burst_keystrokes", Double(key.count), 0)
        out("typing_burst_cpu_ms_per_keystroke", busy * 1000 / Double(key.count))
        out("typing_burst_cpu_percent_one_core", 100 * busy / wall, 0)
        panel.hide()
        await sleep(0.2)

        // 200 open, type, close cycles.
        for i in 0..<200 {
            app.showPanel()
            for c in ["saf", "code", "12*3", "zzz"][i % 4] { app.model.query.append(c) }
            view.displayIfNeeded()
            panel.hide()
            await sleep(0.06)
        }
        await sleep(0.5)
        memoryReport("after_200_cycles")

        // Warm the icon cache: show rows for every letter, so most installed apps draw an icon.
        app.showPanel()
        for c in "abcdefghijklmnopqrstuvwxyz" {
            app.model.query = String(c)
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            await sleep(0.01)
        }
        panel.hide()
        await sleep(0.5)
        memoryReport("icon_cache_warm")

        print("BENCH ready_for_leaks=\(getpid())")
        fflush(stdout)
        await sleep(20)
        NSApp.terminate(nil)
    }
}
#endif
