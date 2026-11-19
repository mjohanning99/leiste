// Switching desktops from the bar (clicks and the scroll wheel), showing the
// new desktop's buttons straight away, and looking afresh once macOS
// announces that a switch has happened.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	func scroll(_ delta: CGFloat, precise: Bool) {
		guard overDesktops else { return }
		wheel += delta
		let enough: CGFloat = precise ? 24 : 1
		guard abs(wheel) >= enough, Date().timeIntervalSince(lastWheelMove) > 0.35 else { return }
		let display = displays.first { $0.id == overDesktopsDisplay }
		let info = display.flatMap { desktopsOn[$0.id] } ?? desktops
		let next = info.current + (wheel < 0 ? 1 : -1)	// down or right goes to the next desktop
		wheel = 0
		lastWheelMove = Date()
		if next >= 1, next <= info.count { goToDesktop(next, on: display) }
	}

	/// Goes to desktop `n` of a screen (the main one if none is given).
	func goToDesktop(_ n: Int, on display: Display?) {
		if let display, !display.isMain, displays.count > 1 {
			// Another screen with desktops of its own: just switch; the bar follows
			// when macOS says so.
			Desktops.go(to: n, from: desktopsOn[display.id] ?? desktops)
			return
		}
		goToDesktop(n)
	}

	func goToDesktop(_ n: Int) {
		let from = desktops
		showAhead(n)
		Desktops.go(to: n, from: from)
	}

	/// A desktop switch is on its way (clicked in the bar or scrolled to):
	/// show that desktop's buttons and number at once, before macOS has even
	/// begun to slide over.
	func showAhead(_ n: Int) {
		guard n != desktops.current, n >= 1, n <= desktops.count, !fullScreen else { return }
		if desktops.spaceIDs.indices.contains(n - 1), let remembered = byDesktop[desktops.spaceIDs[n - 1]] {
			windows = remembered
		}
		desktops.current = n
		settlingUntil = Date().addingTimeInterval(1.6)
		// Held until macOS has slid over and says so (at most 1.6 seconds): mid-slide,
		// macOS still reports the old desktop, which would put its buttons back.
		holdingUntil = Date().addingTimeInterval(1.6)
		// If macOS never says so (the switch didn't happen), look again once the hold is over.
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1650)) { [weak self] in self?.refresh() }
	}

	/// The desktop changed (macOS says so once its slide is over). The bar looks
	/// at once and a few more times, to catch windows that arrive a little late.
	func desktopChanged() {
		holdingUntil = .distantPast	// macOS has arrived; what it reports is right again
		settlingUntil = Date().addingTimeInterval(0.9)
		lookAfresh("switched")
		for ms in [100, 250, 500, 800, 1500] {
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in self?.lookAfresh("\(ms) ms after") }
		}
	}

	/// After a desktop switch, every app is asked afresh: mid-slide, the new
	/// desktop's windows can already be on screen while their apps don't list
	/// them yet, and the verdict "not a window" mustn't outlive the slide.
	func lookAfresh(_ when: String) {
		notWindows = [:]
		changedApps.formUnion(known.keys)
		changedApps.formUnion(Watch.pids)
		refresh()
		// Only an odd moment is noted: windows on screen but no buttons for them.
		if windows.isEmpty, !frames.isEmpty, Date() > settlingUntil {
			Log.write("desktop \(desktops.current) \(when): \(frames.count) windows on screen but no buttons")
		}
	}
}
