// "Minimise into Leiste": instead of macOS's minimise, whose animation the
// Dock draws and always aims at the Dock, the window is parked in the
// screen's bottom-right corner, all but one point of it out of sight (the
// trick AeroSpace uses for its desktops), while a glass stand-in (Ghost.swift)
// shrinks into its button on the bar. Clicking the button grows it back out.
//
// It isn't a real minimise, so other apps don't know about it: Mission
// Control shows a tucked window as a tiny one in the corner. If a tucked
// window comes to the front by other means (⌘Tab), Leiste brings it back.
// Where each tucked window belongs is also written to tucked.txt, so that if
// Leiste stops unexpectedly it puts them back when it next starts.

import AppKit
import ApplicationServices

struct Tucked {
	let pid: pid_t
	let element: AXUIElement
	let frame: CGRect	// where the window was, in accessibility coordinates (top left of the main screen)
}

extension BarModel {
	/// Each screen's bar panel frame (AppKit coordinates), set by the app when it places the bars.
	nonisolated(unsafe) static var panelFrames: [CGDirectDisplayID: CGRect] = [:]

	/// A button's frame in its bar (from SwiftUI) as a rectangle on screen in
	/// accessibility coordinates, which measure down from the top of the main screen.
	func screenRect(ofButton id: CGWindowID) -> CGRect? {
		guard let b = buttonFrames[id], let p = Self.panelFrames[b.display], let main = NSScreen.screens.first else { return nil }
		return CGRect(x: p.minX + b.frame.minX, y: main.frame.height - p.maxY + b.frame.minY,
					  width: b.frame.width, height: b.frame.height)
	}

	/// Whether a window is sitting in a hiding place: the bottom-right corner of
	/// any screen (accessibility coordinates).
	static func isParked(_ r: CGRect) -> Bool {
		MainActor.assumeIsolated {
			Display.all().contains { r.minX >= $0.axFrame.maxX - 3 && r.minY >= $0.axFrame.maxY - 3 }
		}
	}

	func tuck(_ w: BarWindow) {
		// A window still flying ignores clicks until it lands, so quick clicks can't muddle it.
		guard !flying.contains(w.id), tucked[w.id] == nil else { return }
		guard let el = elements[w.id], let screen = NSScreen.screens.first,
			  let pos: CGPoint = Self.value(el, kAXPositionAttribute, .cgPoint, CGPoint.zero),
			  let size: CGSize = Self.value(el, kAXSizeAttribute, .cgSize, CGSize.zero) else { minimiseForReal(w); return }
		var from = CGRect(origin: pos, size: size)
		// Never take the hiding place for the window's home.
		if Self.isParked(from) { from = homes[w.id] ?? Self.middle(of: size) }
		homes[w.id] = from
		flying.insert(w.id)
		tucked[w.id] = Tucked(pid: w.pid, element: el, frame: from)
		saveTucked()
		// The hiding place is the bottom-right corner of the window's own screen.
		let home = Display.containing(from, in: displays) ?? displays.first
		let edge = home?.axFrame ?? CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
		let target = screenRect(ofButton: w.id) ?? CGRect(x: from.midX - 60, y: edge.maxY - 40, width: 120, height: 30)
		let corner = CGPoint(x: edge.maxX - 1, y: edge.maxY - 1)
		let icon = NSRunningApplication(processIdentifier: w.pid)?.icon
		// The pane takes the window's place first, then the window goes to the
		// corner in one move (at its own size, so bringing it back is only a move).
		Ghost.fly(icon: icon, window: from, button: target, shrinking: true) {
			self.flying.remove(w.id)
			self.refreshSoon()
		}
		DispatchQueue.main.async {
			Self.setFrame(el, CGRect(origin: corner, size: from.size))
			self.focusNext(after: w.id)
			self.refresh()
		}
	}

	func untuck(_ id: CGWindowID, animated: Bool = true, then: (() -> Void)? = nil) {
		guard animated == false || !flying.contains(id), let t = tucked.removeValue(forKey: id) else { return }
		saveTucked()
		// The pane grows out of the button; at the end the window is put back in one move.
		if animated, let start = screenRect(ofButton: id) {
			flying.insert(id)
			Ghost.fly(icon: NSRunningApplication(processIdentifier: t.pid)?.icon, window: t.frame, button: start, shrinking: false) {
				Self.setFrame(t.element, t.frame)
				self.flying.remove(id)
				then?()
				self.refreshSoon()
			}
		} else {
			Self.setFrame(t.element, t.frame)
			then?()
		}
	}

	/// A sensible place for a window with no home: the middle of the main screen.
	static func middle(of size: CGSize) -> CGRect {
		guard let s = NSScreen.screens.first?.visibleFrame, let full = NSScreen.screens.first?.frame else { return CGRect(origin: .zero, size: size) }
		let w = min(size.width, s.width * 0.8), h = min(size.height, s.height * 0.8)
		return CGRect(x: s.midX - w / 2, y: full.height - s.midY - h / 2, width: w, height: h)
	}

	/// Self-healing, once a second: any window sitting in the hiding place that
	/// Leiste isn't hiding (after a mishap, or left over from last time) goes
	/// back to its last known place, or to the middle of the screen.
	func healParked() {
		guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
		for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
			guard let id = info[kCGWindowNumber as String] as? CGWindowID, tucked[id] == nil, !flying.contains(id),
				  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
				  let b = info[kCGWindowBounds as String] as? [String: Double],
				  Self.isParked(CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)) else { continue }
			let el = elements[id] ?? Self.axWindows(of: AXUIElementCreateApplication(pid)).first { Self.windowID($0) == id }
			guard let el else { continue }
			let size = CGSize(width: b["Width"] ?? 800, height: b["Height"] ?? 600)
			Self.setFrame(el, homes[id] ?? Self.middle(of: size))
			Log.write("brought window \(id) back from the hiding place")
		}
	}

	/// Looks again once the stand-in has gone (the bar doesn't look while it flies).
	func refreshSoon() {
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in self?.refresh() }
	}

	/// Puts every tucked window back where it was, at once (when Leiste quits).
	func untuckAll() {
		for id in Array(tucked.keys) { untuck(id, animated: false) }
	}

	static func setFrame(_ el: AXUIElement, _ r: CGRect) {
		var origin = r.origin, size = r.size
		if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, p) }
		if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, s) }
		if let p = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, p) }
	}

	// MARK: Keeping a note, in case Leiste stops unexpectedly

	private static var tuckedFile: URL { Settings.folder.appendingPathComponent("tucked.txt") }

	/// One line per tucked window: its number, its app's process number and where it was.
	private func saveTucked() {
		let lines = tucked.map { id, t in "\(id) \(t.pid) \(t.frame.minX) \(t.frame.minY) \(t.frame.width) \(t.frame.height)" }
		if lines.isEmpty { try? FileManager.default.removeItem(at: Self.tuckedFile); return }
		try? (lines.joined(separator: "\n") + "\n").write(to: Self.tuckedFile, atomically: true, encoding: .utf8)
	}

	/// Puts back windows that were still tucked when Leiste last stopped.
	func restoreTuckedFromLastTime() {
		guard let text = try? String(contentsOf: Self.tuckedFile, encoding: .utf8) else { return }
		for line in text.split(separator: "\n") {
			let f = line.split(separator: " ").compactMap { Double($0) }
			guard f.count == 6 else { continue }
			let app = AXUIElementCreateApplication(pid_t(f[1]))
			for el in Self.axWindows(of: app) where Self.windowID(el) == CGWindowID(f[0]) {
				Self.setFrame(el, CGRect(x: f[2], y: f[3], width: f[4], height: f[5]))
			}
		}
		try? FileManager.default.removeItem(at: Self.tuckedFile)
	}
}
