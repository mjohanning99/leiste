// Keeping windows above the bar. macOS can reserve room at the screen's edge
// only for the Dock, so window tilers and the green button size windows down
// to the bottom edge, under the bar. Like a Plasma panel, Leiste shortens them.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// Apple gives no way to reserve room for a bar (only the Dock can), so
	/// window tilers (Swish) and the green button size windows down to the
	/// screen's bottom edge, under the bar, or centre them over the whole
	/// screen. Like a Plasma panel, we shorten the first and move the second up,
	/// to end a gap above the bar. Only windows that reach the bottom edge are touched
	/// and never while a mouse button is down (you may be dragging one); then
	/// it looks again once the button is up.
	func fitAboveBar() {
		guard trusted else { return }
		let mouseDown = NSEvent.pressedMouseButtons != 0
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
			guard bottom > limit + 1, bottom <= f.maxY + 2,		// reaching under the bar, not pushed off the screen
				  pos.y < limit - 120 else { continue }			// and tall enough to fit
			// Sized down to the bottom edge (the green button, "fill the screen"): it is
			// shortened. Placed partly under the bar instead (a tiler centring it over
			// the whole screen): it is moved up, and shortened only if it doesn't fit.
			// Never a window you dragged there yourself.
			let toEdge = bottom >= f.maxY - 24
			if !toEdge, movedByHand[id] == true { continue }
			// A window under the bar while the mouse is held: once it's let go.
			if mouseDown { fitAgain(after: 0.3); continue }
			// Tilers (Swish) glide a window into place; fitting it mid-glide only
			// starts a tug of war. Wait until it has kept still for a quarter second.
			let now0 = Date()
			if settling[id]?.frame != r { settling[id] = (r, now0) }
			if let since = settling[id]?.since, now0.timeIntervalSince(since) < 0.25 { fitAgain(after: 0.3); continue }
			// An app that sets its size straight back would be resized again and
			// again: after four times in 20 seconds it is left alone for a while.
			// Otherwise at most once a second, looking again when the second is up
			// (you may well snap the same window twice in a row).
			let now = Date()
			let recent = (shortenedAt[id] ?? []).filter { now.timeIntervalSince($0) < 20 }
			if recent.count >= 4 { continue }
			if let last = recent.last, now.timeIntervalSince(last) < 1 { fitAgain(after: 1.1); continue }
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
			var top = pos.y
			if !toEdge {
				// Up until it ends above the bar, but not under the menu bar.
				top = max(disp.axTop, limit - size.height)
				var moved = CGPoint(x: pos.x, y: top)
				if let v = AXValueCreate(.cgPoint, &moved) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
			}
			var fitted = CGSize(width: size.width, height: limit - top)
			if fitted.height < size.height - 0.5, let v = AXValueCreate(.cgSize, &fitted) {
				AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
			}
			shortenedAt[id] = recent + [now]
			if recent.count == 3 { Log.write("window \(id) keeps growing back under the bar: left alone for a while") }
			Log.write(toEdge ? "shortened window \(id) to end above the bar (\(Int(size.height)) → \(Int(fitted.height)) high)"
							 : "moved window \(id) up out from under the bar (top \(Int(pos.y)) → \(Int(top)), \(Int(fitted.height)) high)")
		}
	}

	/// Looks again in a moment (once, however often it is asked meanwhile).
	private func fitAgain(after seconds: Double) {
		guard !fitAgainSoon else { return }
		fitAgainSoon = true
		DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
			self?.fitAgainSoon = false
			self?.refresh()
		}
	}
}
