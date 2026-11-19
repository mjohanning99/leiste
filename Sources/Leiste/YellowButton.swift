// With "Minimise into Leiste" on, a click on a window's own yellow button
// tucks the window into Leiste too, instead of letting the app send it to the
// Dock. Leiste listens to mouse clicks (with the Accessibility permission it
// already has). For speed it only looks closer when a click lands where a
// window's three buttons are, its top-left corner; every other click passes
// straight through untouched.
//
// ⌘M (the keyboard's minimise) still goes to the Dock: catching keys would
// need another permission, Input Monitoring.

import AppKit
import ApplicationServices

@MainActor
enum YellowButton {
	/// Called with the window's number when its yellow button is clicked.
	static var onClick: ((CGWindowID) -> Void)?
	private static var tap: CFMachPort?
	private static var swallowNextUp = false

	static func install() {
		guard tap == nil else { return }	// already listening
		let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
		guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
										  eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
			MainActor.assumeIsolated { YellowButton.handle(type, event) }
		}, userInfo: nil) else {
			Log.write("could not listen for clicks on yellow buttons")
			return
		}
		self.tap = tap
		CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
	}

	private static func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
		// macOS switches a listener off if it is ever too slow; switch it back on.
		if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
			if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
			return Unmanaged.passUnretained(event)
		}
		if type == .leftMouseUp, swallowNextUp {
			swallowNextUp = false
			return nil
		}
		guard type == .leftMouseDown, Prefs.shared.minimiseInto == .leiste,
			  let id = yellowButtonWindow(at: event.location) else { return Unmanaged.passUnretained(event) }
		// The click is ours: the app never sees it, so it never minimises to the Dock.
		swallowNextUp = true
		DispatchQueue.main.async { onClick?(id) }
		return nil
	}

	/// The window whose yellow button is at `point` (accessibility coordinates), if any.
	private static func yellowButtonWindow(at point: CGPoint) -> CGWindowID? {
		// Quick test first, from what the bar already knows: is the click near the
		// top-left corner of a window on screen? Most clicks stop here.
		let near = BarModel.onScreenFrames.contains { f in
			let x = point.x - f.minX, y = point.y - f.minY
			return x >= 0 && x <= 90 && y >= 0 && y <= 52
		}
		guard near else { return nil }
		// Then ask accessibility what is under the pointer.
		let system = AXUIElementCreateSystemWide()
		AXUIElementSetMessagingTimeout(system, 0.1)
		var hit: AXUIElement?
		guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit,
			  (BarModel.attribute(hit, kAXSubroleAttribute) as? String) == (kAXMinimizeButtonSubrole as String),
			  let window = BarModel.attribute(hit, kAXWindowAttribute) else { return nil }
		return BarModel.windowID(window as! AXUIElement)
	}
}
