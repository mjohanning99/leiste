// What clicks on the bar do: bringing windows forward, minimising them (to the
// Dock or into Leiste), closing them, grouping windows by app and cycling
// through a group, the keyboard shortcuts, the middle button and dragging
// buttons to a new place.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// The buttons to show: one per window, or one per app when grouped.
	/// "Crowded" groups once the buttons would get narrower than 130 points.
	/// The windows a screen's bar shows: its own (Screens: each), or all of them.
	func windows(on display: Display?) -> [BarWindow] {
		guard let display, Prefs.shared.screens == .each, displays.count > 1 else { return windows }
		return windows.filter { (screenOf[$0.id] ?? displays.first?.id) == display.id }
	}

	func groups(width: CGFloat, display: Display? = nil) -> [WindowGroup] {
		let windows = windows(on: display)
		let remember = display == nil || display?.isMain == true	// the keyboard shortcuts use the main bar's buttons
		let single = windows.map { WindowGroup(id: "w\($0.id)", windows: [$0]) }
		let group: Bool
		switch grouping {
		case .never: group = false
		case .always: group = true
		case .crowded: group = width / CGFloat(max(windows.count, 1)) < 130
		}
		guard group else { if remember { shownGroups = single }; return single }
		var result: [WindowGroup] = []
		for w in windows {
			let key = w.bundleID ?? "p\(w.pid)"
			if let i = result.firstIndex(where: { $0.id == key }) { result[i].windows.append(w) }
			else { result.append(WindowGroup(id: key, windows: [w])) }
		}
		if remember { shownGroups = result }
		return result
	}

	func setGrouping(_ g: Grouping) { Prefs.shared.grouping = g }

	/// A click on a group's button: the latest of its windows comes forward,
	/// and each further click brings the next one, round and round.
	func click(_ g: WindowGroup) {
		guard g.windows.count > 1 else { click(g.windows[0]); return }
		if let i = g.windows.firstIndex(where: \.isActive) {
			raise(g.windows[(i + 1) % g.windows.count])
		} else {
			raise(g.windows.max { (lastFront[$0.id] ?? .distantPast) < (lastFront[$1.id] ?? .distantPast) }!)
		}
	}

	/// Control-Option-n: the n-th button, as a click would but never minimising.
	func pressShortcut(_ n: Int) {
		guard shownGroups.indices.contains(n - 1) else { return }
		let g = shownGroups[n - 1]
		if g.windows.count == 1 { raise(g.windows[0]) } else { click(g) }
	}

	/// The middle button (pressing the wheel) opens a new window of the app under the pointer.
	func middleClick() {
		if let id = pointedApp { newWindow(id) }
	}

	/// A click on a window's button: bring it forward, or minimise it if it is
	/// already in front, or bring it back if it is minimised (as in Plasma).
	func click(_ w: BarWindow) {
		if w.isActive { minimise(w) } else { raise(w) }
	}

	func raise(_ w: BarWindow) {
		if flying.contains(w.id) { return }	// still flying; it ignores clicks until it lands
		guard let el = elements[w.id] else {
			NSRunningApplication(processIdentifier: w.pid)?.activate()
			return
		}
		if tucked[w.id] != nil {
			untuck(w.id)
		} else if w.isMinimised {
			AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
			minimised[w.id] = nil
		}
		AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
		AXUIElementPerformAction(el, kAXRaiseAction as CFString)
		NSRunningApplication(processIdentifier: w.pid)?.activate()
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in self?.refresh() }
	}

	/// Minimises a window: into the Dock as macOS does, or into Leiste (Tuck.swift).
	func minimise(_ w: BarWindow) {
		if Prefs.shared.minimiseInto == .leiste { tuck(w) } else { minimiseForReal(w) }
	}

	/// After a window is tucked, the next window down comes to the front, as
	/// after a real minimise, so typing never goes into the tucked one.
	func focusNext(after id: CGWindowID) {
		let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
		for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
			guard let wid = info[kCGWindowNumber as String] as? CGWindowID, wid != id, tucked[wid] == nil,
				  let el = elements[wid], let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
			AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
			AXUIElementPerformAction(el, kAXRaiseAction as CFString)
			NSRunningApplication(processIdentifier: pid)?.activate()
			return
		}
		// Nothing else here: Finder, so the desktop is in front.
		NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
	}

	func minimiseForReal(_ w: BarWindow) {
		guard let el = elements[w.id] else { return }
		AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
		// Keep it on the bar straight away rather than waiting for the next look.
		minimised[w.id] = (w.pid, el, w.title)
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in self?.refresh() }
	}

	/// Closes a window, as its red button would.
	func close(_ w: BarWindow) {
		guard let el = elements[w.id], let button = Self.attribute(el, kAXCloseButtonAttribute) else { return }
		AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
	}

	func quit(_ bundleID: String) {
		NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
	}

	func isRunning(_ bundleID: String) -> Bool {
		!NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
	}

	/// Moves a button `steps` places along (negative is left). A group moves
	/// all its windows together. Says how many places it really moved (fewer
	/// at either end), so a button being dragged stays under the pointer.
	@discardableResult func move(_ group: WindowGroup, by steps: Int, among groups: [WindowGroup]) -> Int {
		guard steps != 0, let from = groups.firstIndex(where: { $0.id == group.id }) else { return 0 }
		var g = groups
		let item = g.remove(at: from)
		let to = max(0, min(g.count, from + steps))
		guard to != from else { return 0 }
		g.insert(item, at: to)
		// The new order of this desktop's windows goes into the places they had in
		// the order of all desktops, so the other desktops' orders stay as they were.
		let mine = g.flatMap { $0.windows.map(\.id) }
		let ids = Set(mine)
		let slots = order.indices.filter { ids.contains(order[$0]) }
		if slots.count == mine.count {
			for (k, i) in slots.enumerated() { order[i] = mine[k] }
		} else {
			order = mine + order.filter { !ids.contains($0) }
		}
		let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
		windows = mine.compactMap { byID[$0] }
		return to - from
	}

	// MARK: Dropping a window's button onto a desktop number

	/// Whether `point` (in the bar's own coordinates) is over a desktop number
	/// of this screen's switcher, other than the desktop you're on. Lights that
	/// number up while it is.
	func desktopNumber(at point: CGPoint, display: CGDirectDisplayID) -> Bool {
		var n: Int?
		if Prefs.shared.dropOnDesktop {
			let current = desktopsOn[display]?.current ?? desktops.current
			n = desktopFrames[display]?.first { $0.key != current && $0.value.insetBy(dx: -2, dy: -10).contains(point) }?.key
		}
		if n != dropTarget?.desktop || (n != nil && dropTarget?.display != display) {
			dropTarget = n.map { (display, $0) }
		}
		return n != nil
	}

	/// Moves a dropped button's window (the one in front, for a group) to the
	/// desktop it was dropped on.
	func dropOnDesktop(_ group: WindowGroup) {
		guard let target = dropTarget else { return }
		dropTarget = nil
		move(group.windows.first(where: \.isActive) ?? group.first, toDesktop: target.desktop)
	}
}
