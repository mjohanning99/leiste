// Pinned apps: opening a new window of an app on the desktop you're on (⌘N
// sent in the background), or going to the window it has, and the list of
// pinned apps itself. Also how to tell an app's real windows from the
// invisible ones apps keep.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// Which pinned apps are open, for the dots. Updated when an app opens or quits.
	func readRunning() {
		let r = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)).intersection(launchers.map(\.id))
		if r != running { running = r }
	}

	/// Opens a new window of an app on this desktop.
	func newWindow(_ bundleID: String) {
		Log.write("new window for \(bundleID), on desktop \(desktops.current)")
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
		let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
		// Not running, or running with no windows at all: opening it is enough,
		// because the app makes its first window wherever you are.
		// (The window server is asked, not the app: it knows the windows on every
		// desktop and answers at once.)
		guard let app = running, Self.hasWindowsAnywhere(app.processIdentifier) else {
			Log.write("  not running or no windows: opening the app")
			NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
			return
		}
		// Set to "its window" in the right-click menu (an app whose ⌘N does
		// something else, like a mail app writing a new message): go there.
		if goesToItsWindow.contains(bundleID) {
			goToWindow(of: app)
			return
		}
		// Otherwise ⌘N, sent to the app while it stays in the background, so
		// macOS doesn't take you to its other desktop. A window made then appears
		// on the desktop you're on; if none comes (an app with one window only),
		// you're taken to the window it has.
		let before = Set(Self.windowIDs(of: app.processIdentifier))
		Keys.press(45, flags: .maskCommand, to: app.processIdentifier)	// ⌘N; 45 is N
		waitForNewWindow(app, before: before, tries: 12)
	}

	/// The app's real windows on every desktop, from the window server (no app is
	/// asked). Real means really shown on some desktop: apps also keep invisible
	/// helper windows and closed windows for later (some mail apps do both).
	static func windowIDs(of pid: pid_t) -> [CGWindowID] {
		let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
		return list.compactMap { info in
			let b = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
			guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
				  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 80,
				  let id = info[kCGWindowNumber as String] as? CGWindowID, isShown(id) else { return nil }
			return id
		}
	}

	/// Whether a window is really shown on some desktop: put on screen ("ordered
	/// in") and belonging to a desktop. A closed window that its app keeps for
	/// later is ordered out, even if it still names the desktop it was on.
	static func isShown(_ id: CGWindowID) -> Bool {
		var orderedIn = false
		CGSWindowIsOrderedIn(CGSMainConnectionID(), id, &orderedIn)
		return orderedIn && !spacesOf(id).isEmpty
	}

	/// The desktops a window belongs to (none for an invisible helper window).
	static func spacesOf(_ id: CGWindowID) -> [UInt64] {
		let ids = [NSNumber(value: id)] as CFArray
		guard let list = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, ids)?.takeRetainedValue() as? [NSNumber] else { return [] }
		return list.map { $0.uint64Value }
	}

	/// Watches the window server (every 0.1 seconds, up to 1.2 seconds) for the
	/// app's new window, then brings it forward. The app itself is only asked once
	/// the window exists, and away from the bar, so a slow app never holds it up.
	func waitForNewWindow(_ app: NSRunningApplication, before: Set<CGWindowID>, tries: Int) {
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
			guard let self else { return }
			if let new = Self.windowIDs(of: app.processIdentifier).first(where: { !before.contains($0) }) {
				Log.write("  new window \(new)")
				let pid = app.processIdentifier
				DispatchQueue.global(qos: .userInitiated).async {
					let ax = AXUIElementCreateApplication(pid)
					if let el = Self.axWindows(of: ax).first(where: { Self.windowID($0) == new }) {
						AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
						AXUIElementPerformAction(el, kAXRaiseAction as CFString)
					}
					DispatchQueue.main.async {
						app.activate()
						self.lookSoon()
					}
				}
			} else if tries > 0 {
				self.waitForNewWindow(app, before: before, tries: tries - 1)
			} else {
				Log.write("  no new window: going to the one it has")
				self.goToWindow(of: app)
			}
		}
	}

	func setGoesToItsWindow(_ bundleID: String, _ on: Bool) {
		if on { goesToItsWindow.insert(bundleID) } else { goesToItsWindow.remove(bundleID) }
		Settings.write("go-to-window.txt", header: Settings.goToWindowHeader, ids: goesToItsWindow.sorted())
	}

	/// Goes to the desktop where an app's window is and brings the app forward,
	/// the way the Dock does it (which also makes an app with its window closed
	/// open one).
	func goToWindow(of app: NSRunningApplication) {
		let target = Self.windowIDs(of: app.processIdentifier).lazy
			.compactMap { id in Self.spacesOf(id).compactMap { self.desktops.spaceIDs.firstIndex(of: $0) }.first }.first
		Log.write("  going to its window, on desktop \(target.map { String($0 + 1) } ?? "none (it opens one)")")
		let showIt = {
			guard let url = app.bundleURL else { app.activate(); return }
			let config = NSWorkspace.OpenConfiguration()
			config.activates = true
			NSWorkspace.shared.openApplication(at: url, configuration: config)
		}
		if let n = target, n + 1 != desktops.current {
			goToDesktop(n + 1)
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(450)) { showIt() }
		} else {
			showIt()
		}
	}

	/// Whether an app has ordinary windows on any desktop.
	static func hasWindowsAnywhere(_ pid: pid_t) -> Bool {
		!windowIDs(of: pid).isEmpty
	}

	func launch(_ l: Launcher) { newWindow(l.id) }

	/// Moves a launcher `steps` places along and saves the new order.
	/// Moves a pinned app `steps` places along; says how many it really moved
	/// (fewer at either end).
	@discardableResult func moveLauncher(_ id: String, by steps: Int) -> Int {
		guard steps != 0, let from = launchers.firstIndex(where: { $0.id == id }) else { return 0 }
		var l = launchers
		let item = l.remove(at: from)
		let to = max(0, min(l.count, from + steps))
		guard to != from else { return 0 }
		l.insert(item, at: to)
		launchers = l
		Settings.write("launchers.txt", header: Settings.launchersHeader, ids: l.map(\.id))
		return to - from
	}

	static func loadLaunchers() -> [Launcher] {
		Settings.read("launchers.txt", header: Settings.launchersHeader, defaults: Settings.defaultLaunchers).compactMap { id in
			NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { Launcher(id: id, url: $0) }
		}
	}

	func isPinned(_ bundleID: String) -> Bool { launchers.contains { $0.id == bundleID } }

	/// Pins an app at the right end of the launchers, or unpins it.
	func togglePin(_ bundleID: String) {
		var ids = Settings.read("launchers.txt", header: Settings.launchersHeader, defaults: Settings.defaultLaunchers)
		if ids.contains(bundleID) { ids.removeAll { $0 == bundleID } } else { ids.append(bundleID) }
		Settings.write("launchers.txt", header: Settings.launchersHeader, ids: ids)
		launchers = Self.loadLaunchers()
		readRunning()
	}

	/// Moves pinned apps in the Settings list and saves the new order.
	func moveLaunchers(from: IndexSet, to: Int) {
		var l = launchers
		l.move(fromOffsets: from, toOffset: to)
		launchers = l
		Settings.write("launchers.txt", header: Settings.launchersHeader, ids: l.map(\.id))
	}

	/// The app at `url` (an .app chosen in Settings), by its bundle identifier.
	static func bundleID(of url: URL) -> String? { Bundle(url: url)?.bundleIdentifier }
}
