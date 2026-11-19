// Keeping windows above the bar. macOS can reserve room at the screen's edge
// only for the Dock, so window tilers and the green button size windows down
// to the bottom edge, under the bar. Like a Plasma panel, Leiste shortens them.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// Apple gives no way to reserve room for a bar, so window tilers (Swish)
	/// and the green button size windows down to the screen's bottom edge,
	/// under the bar. Like a Plasma panel, we shorten such windows to end a
	/// gap above the bar. Only windows that reach the bottom edge are touched
	/// and never while a mouse button is down (you may be dragging one).
	func fitAboveBar() {
		guard trusted, NSEvent.pressedMouseButtons == 0 else { return }
		let inset = Prefs.shared.inset
		let barred = Prefs.shared.screens == .main ? Array(displays.prefix(1)) : displays
		// Positions come from the window server's list, so no app is asked unless
		// one of its windows really needs shortening.
		for (id, el) in elements where minimised[id] == nil && tucked[id] == nil {
			guard let r = frames[id], let disp = Display.containing(r, in: displays),
				  barred.contains(disp), !hiddenOn.contains(disp.id) else { continue }
			let f = disp.axFrame
			let limit = f.maxY - Prefs.shared.height - 2 * inset	// the gap above the bar matches the one below it
			let pos = r.origin, size = r.size
			let bottom = pos.y + size.height
			// Once in a few seconds at most: an app that sets its size back would
			// otherwise be resized again and again.
			if let last = shortenedAt[id], Date().timeIntervalSince(last) < 5 { continue }
			guard bottom > limit + 1,							// reaching under the bar
				  bottom >= f.maxY - 24, bottom <= f.maxY + 2,	// sized to the bottom edge, not pushed off it
				  pos.y < limit - 120 else { continue }			// and tall enough to shorten
			// Before changing anything, the window itself is asked where it is. While
			// Mission Control shows windows small, the window server can report their
			// shrunken places; acting on those would resize windows wrongly.
			guard let realPos: CGPoint = Self.value(el, kAXPositionAttribute, .cgPoint, CGPoint.zero),
				  let realSize: CGSize = Self.value(el, kAXSizeAttribute, .cgSize, CGSize.zero),
				  abs(realPos.x - pos.x) < 2, abs(realPos.y - pos.y) < 2,
				  abs(realSize.width - size.width) < 2, abs(realSize.height - size.height) < 2 else {
				Log.write("left window \(id) alone: it isn't where the window server says (Mission Control?)")
				continue
			}
			var fitted = CGSize(width: size.width, height: limit - pos.y)
			if let v = AXValueCreate(.cgSize, &fitted) {
				AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
				shortenedAt[id] = Date()
				Log.write("shortened window \(id) to end above the bar (\(Int(size.height)) → \(Int(fitted.height)) high)")
			}
		}
	}
}
