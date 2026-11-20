// Reading the windows: which windows are on this desktop (and minimised ones),
// what they are called and which is in front, what each app has and the
// windows on every desktop for the "Pictures" switcher. The window server is
// asked first (it answers at once); apps are asked only about what changed.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// Looks again at an app half a second and two seconds after it showed a
	/// window it didn't list yet, forgetting the verdict on its unlisted windows.
	///
	/// At most one pair of extra looks per app at a time, and those looks never
	/// schedule more: otherwise a window its app never lists makes every look
	/// schedule two more, doubling until the bar freezes (it did, 19 November 2026).
	func lookAgainForNewWindows(_ pid: pid_t) {
		guard !lookingAgain.contains(pid) else { return }
		lookingAgain.insert(pid)
		for delay in [500, 2000] {
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) { [weak self] in
				guard let self else { return }
				self.notWindows[pid] = nil
				self.changedApps.insert(pid)
				self.refresh()
				if delay == 2000 { self.lookingAgain.remove(pid) }
			}
		}
	}

	/// Drops what was remembered about windows that no longer exist.
	func forgetClosedWindows() {
		let alive = Set(windows.map(\.id)).union(tucked.keys).union(minimised.keys)
		// The order spans every desktop: only windows that no longer exist anywhere leave it.
		if let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
			let existing = Set(all.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
			order.removeAll { !existing.contains($0) }
		}
		lastFront = lastFront.filter { alive.contains($0.key) }
		lastSpace = lastSpace.filter { alive.contains($0.key) }
		homes = homes.filter { alive.contains($0.key) }
		shortenedAt = shortenedAt.filter { alive.contains($0.key) }
		movedByHand = movedByHand.filter { alive.contains($0.key) }
		settling = settling.filter { alive.contains($0.key) }
		buttonFrames = buttonFrames.filter { alive.contains($0.key) }
		let pids = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
		apps = apps.filter { pids.contains($0.key) }
		known = known.filter { pids.contains($0.key) }
		notWindows = notWindows.filter { pids.contains($0.key) }
	}

	/// An app's name and icon, looked up the first time only.
	func info(_ pid: pid_t) -> AppInfo {
		if let known = apps[pid] { return known }
		let app = NSRunningApplication(processIdentifier: pid)
		let made = AppInfo(bundleID: app?.bundleIdentifier, name: app?.localizedName ?? "Window", icon: app?.icon)
		apps[pid] = made
		return made
	}

	/// Finds the minimised windows of every app. They aren't on screen, so the
	/// window server's list leaves them out; accessibility still knows them.
	func readMinimised() {
		guard trusted else { minimised = [:]; return }
		var found: [CGWindowID: (pid: pid_t, element: AXUIElement, title: String)] = [:]
		// The apps Leiste listens to are exactly the ones with windows (Watch.swift).
		for pid in Watch.pids {
			let ax = AXUIElementCreateApplication(pid)
			AXUIElementSetMessagingTimeout(ax, 0.1)
			for el in Self.axWindows(of: ax) where (Self.attribute(el, kAXMinimizedAttribute) as? Bool) == true {
				var wid: CGWindowID = 0
				guard _AXUIElementGetWindow(el, &wid) == .success else { continue }
				found[wid] = (pid, el, Self.attribute(el, kAXTitleAttribute) as? String ?? "")
			}
		}
		minimised = found
	}

	/// Every ordinary window on every desktop, placed on its desktop's picture.
	func readDesktopPictures() {
		guard let screen = NSScreen.screens.first,
			  let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
		let f = screen.frame
		var result: [Int: [CGRect]] = [:]
		for info in list {
			let b = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
			guard (info[kCGWindowLayer as String] as? Int) == 0,
				  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
				  (info[kCGWindowOwnerPID as String] as? pid_t) != getpid(),
				  let id = info[kCGWindowNumber as String] as? CGWindowID,
				  (b["Width"] ?? 0) >= 120, (b["Height"] ?? 0) >= 80, minimised[id] == nil, tucked[id] == nil else { continue }
			let rect = CGRect(x: (b["X"] ?? 0) / f.width, y: (b["Y"] ?? 0) / f.height,
							  width: (b["Width"] ?? 0) / f.width, height: (b["Height"] ?? 0) / f.height)
			for space in spaces(of: id) {
				if let n = desktops.spaceIDs.firstIndex(of: space) { result[n + 1, default: []].append(rect) }
			}
		}
		if result != desktopPictures { desktopPictures = result }
	}

	/// The desktops a window belongs to, as the window server numbers them.
	func spaces(of id: CGWindowID) -> [UInt64] {
		let ids = [NSNumber(value: id)] as CFArray
		guard let list = CGSCopySpacesForWindows(CGSMainConnectionID(), 7, ids)?.takeRetainedValue() as? [NSNumber] else { return [] }
		return list.map { $0.uint64Value }
	}

	func readWindows() -> [BarWindow] {
		// The window server lists every window that is on screen now, which is
		// exactly the windows of the current desktop (minimised ones aren't on it).
		let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
		guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
		let me = getpid()
		let space = CGSGetActiveSpace(CGSMainConnectionID())

		var found: [CGWindowID: pid_t] = [:]
		var onScreen: [CGWindowID: CGRect] = [:]
		for info in list {
			guard (info[kCGWindowLayer as String] as? Int) == 0,	// ordinary windows, not menus or panels
				  let id = info[kCGWindowNumber as String] as? CGWindowID,
				  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
				  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
			let b = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
			if (b["Width"] ?? 0) < 60 || (b["Height"] ?? 0) < 40 { continue }
			found[id] = pid
			onScreen[id] = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
		}

		// The accessibility side gives each window's title and tells real
		// windows from odd ones (a floating palette, an invisible helper).
		var titles: [CGWindowID: String] = [:]
		elements = [:]
		if trusted {
			var byApp: [pid_t: [CGWindowID]] = [:]
			for (id, pid) in found { byApp[pid, default: []].append(id) }
			for (pid, ids) in byApp {
				let remembered = known[pid] ?? [:]
				let skip = (notWindows[pid] ?? [:]).filter { Date().timeIntervalSince($0.value) < 3 }
				// Asked again only if it announced a change or shows a window we haven't met.
				let unknown = ids.contains(where: { remembered[$0] == nil && skip[$0] == nil })
				if changedApps.contains(pid) || unknown {
					var mine: [CGWindowID: (element: AXUIElement, title: String)] = [:]
					var others: [CGWindowID: Date] = skip
					let app = AXUIElementCreateApplication(pid)
					AXUIElementSetMessagingTimeout(app, 0.25)	// so a stuck app can't stall the bar
					for el in Self.axWindows(of: app) {
						var wid: CGWindowID = 0
						guard _AXUIElementGetWindow(el, &wid) == .success else { continue }
						let subrole = Self.attribute(el, kAXSubroleAttribute) as? String
						if subrole != nil && subrole != (kAXStandardWindowSubrole as String) {
							if others[wid] == nil { others[wid] = Date() }
							continue
						}
						mine[wid] = (el, Self.attribute(el, kAXTitleAttribute) as? String ?? "")
						others[wid] = nil
					}
					// Windows the app didn't list (yet) wait 3 seconds before being asked about again.
					var unlisted = false
					for id in ids where mine[id] == nil && others[id] == nil {
						others[id] = Date()
						unlisted = true
					}
					known[pid] = mine
					notWindows[pid] = others
					// A window just met but not listed yet: look again shortly, when it usually is.
					if unknown && unlisted { lookAgainForNewWindows(pid) }
				}
				for id in ids {
					if let w = known[pid]?[id] { elements[id] = w.element; titles[id] = w.title }
				}
			}
			changedApps = []
			// Without a matching accessibility window it isn't one you'd want on the bar.
			found = found.filter { elements[$0.key] != nil }
		}
		for id in found.keys { lastSpace[id] = space }
		frames = onScreen
		Self.onScreenFrames = Array(onScreen.values)
		// Which screen each window is on; minimised and tucked windows keep the last one.
		var screens = screenOf.filter { minimised[$0.key] != nil || tucked[$0.key] != nil }
		for (id, r) in onScreen where tucked[id] == nil { if let d = Display.containing(r, in: displays) { screens[id] = d.id } }
		if screens != screenOf { screenOf = screens }

		// Minimised windows belong to the desktop they were minimised on.
		var mins: Set<CGWindowID> = []
		for (id, m) in minimised where found[id] == nil {
			let homes = spaces(of: id)
			let here = homes.isEmpty ? (lastSpace[id].map { $0 == space } ?? true) : homes.contains(space)
			guard here else { continue }
			found[id] = m.pid
			elements[id] = m.element
			titles[id] = m.title
			mins.insert(id)
		}

		// Tucked windows are still on screen (parked in the corner); show them faded.
		for id in tucked.keys where found[id] != nil { mins.insert(id) }

		let active = activeWindowID()
		activeID = active
		if let active { lastFront[active] = Date() }
		// A tucked window that comes forward by other means (⌘Tab) comes back out.
		// Not just after a desktop switch, though: with every window there tucked
		// away, macOS hands the keyboard to a parked one by itself.
		if let active, active != previousActive, tucked[active] != nil, NSEvent.pressedMouseButtons == 0,
		   Date().timeIntervalSince(switchedAt) > 2 {
			DispatchQueue.main.async { [weak self] in self?.untuck(active) }
		}
		previousActive = active
		// Windows on other desktops keep their place (closed ones are dropped in
		// forgetClosedWindows), so an order you dragged survives switching away.
		for id in found.keys.sorted() where !order.contains(id) { order.append(id) }

		return order.compactMap { id in
			guard let pid = found[id] else { return nil }
			let app = info(pid)
			let title = titles[id].flatMap { $0.isEmpty ? nil : $0 } ?? app.name
			return BarWindow(id: id, pid: pid, bundleID: app.bundleID, title: title, appName: app.name,
							 icon: app.icon, isActive: id == active && !mins.contains(id), isMinimised: mins.contains(id))
		}
	}

	/// The window you are typing into: the focused window of the app in front.
	func activeWindowID() -> CGWindowID? {
		guard trusted, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
		let app = AXUIElementCreateApplication(pid)
		AXUIElementSetMessagingTimeout(app, 0.25)
		guard let value = Self.attribute(app, kAXFocusedWindowAttribute) else { return nil }
		var wid: CGWindowID = 0
		return _AXUIElementGetWindow((value as! AXUIElement), &wid) == .success ? wid : nil
	}
}
