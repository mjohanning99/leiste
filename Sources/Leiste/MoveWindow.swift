// Moving a window to another desktop (right-click → Move to Desktop). macOS
// has no way for an app to do this, except one: a window being dragged goes
// along when you switch desktops. So Leiste does what your hand would do: it
// presses the mouse on the window's title bar, moves it a hair, presses the
// desktop's shortcut (Control and its number, or Control and an arrow per
// step), lets go once macOS has slid over, and puts the pointer back.
// You end up on the new desktop with the window; that is how macOS does it.
// Window managers use the same trick. If a macOS update closes it, this is
// the file to remove.

import AppKit

extension BarModel {
	func move(_ w: BarWindow, toDesktop n: Int) {
		guard n != desktops.current, n >= 1, n <= desktops.count, !w.isMinimised,
			  let frame = Self.windowIDsFrame(w.id) else { return }
		Log.write("move window \(w.id) to desktop \(n)")
		// Bring it to the front first, so the press lands on it.
		raise(w)
		let grab = CGPoint(x: frame.midX, y: frame.minY + 6)	// the title bar, clear of its buttons
		let back = CGEvent(source: nil)?.location ?? grab
		let from = desktops
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
			func mouse(_ type: CGEventType, _ at: CGPoint) {
				CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
			}
			mouse(.mouseMoved, grab)
			mouse(.leftMouseDown, grab)
			// A small drag, so macOS knows the window is being carried.
			for dx in [2.0, 4.0, 6.0] { mouse(.leftMouseDragged, CGPoint(x: grab.x + dx, y: grab.y)) }
			let held = CGPoint(x: grab.x + 6, y: grab.y)
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
				// Straight there with "Switch to Desktop n", or one step at a time.
				var steps = 1
				if n <= 9, let key = Desktops.shortcut(117 + n) {
					Keys.press(key.code, flags: key.flags)
				} else if let key = Desktops.shortcut(n > from.current ? 81 : 79) {
					steps = abs(n - from.current)
					for i in 0..<steps {
						DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 350)) { Keys.press(key.code, flags: key.flags) }
					}
				}
				// Let go once the slide is over, then put the pointer back.
				DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700 + (steps - 1) * 350)) {
					mouse(.leftMouseUp, held)
					CGWarpMouseCursorPosition(back)
					CGAssociateMouseAndMouseCursorPosition(1)
					Log.write("  let go; now on desktop \(Desktops.read().current)")
				}
			}
		}
	}

	/// Where a window is on screen (accessibility coordinates), from the window server.
	static func windowIDsFrame(_ id: CGWindowID) -> CGRect? {
		guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
			  let b = list.first?[kCGWindowBounds as String] as? [String: Double] else { return nil }
		return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
	}
}
