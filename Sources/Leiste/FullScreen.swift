// Stepping aside for full screen. Each screen's bar fades away while that
// screen shows something full screen: macOS's own full screen (an app on a
// desktop of its own), a window covering the whole screen (as browsers do for
// videos), or a window saying it is going full screen, also while macOS is
// still sliding over to its desktop. Into full screen the bar hides at once;
// out of it, only after 0.15 seconds of calm, so it never blinks.

import AppKit
import ApplicationServices

extension BarModel {
	/// Works out which screens show something full screen (called from refresh()).
	func updateFullScreen(_ ds: [Display], _ all: [CGDirectDisplayID: DesktopInfo]) {
		// Full screen, per screen: macOS's own (a space of its own), a window
		// covering the whole screen (as browsers do for videos), or the window in
		// front saying it is going full screen (also while macOS slides over to its
		// own desktop, when it isn't on any desktop the bar can see).
		var saysFull: CGDirectDisplayID?
		if let id = activeID, let el = elements[id], (Self.attribute(el, "AXFullScreen") as? Bool) == true { saysFull = screenOf[id] }
		if let w = fullWindow {
			if (Self.attribute(w, "AXFullScreen") as? Bool) == true { saysFull = saysFull ?? fullWindowScreen } else { fullWindow = nil }
		}
		var fullNow: Set<CGDirectDisplayID> = []
		for disp in ds {
			let ownDesktop = !(all[disp.id]?.onDesktop ?? true)
			let covering = activeID.flatMap { frames[$0] }.map {
				abs($0.width - disp.axFrame.width) < 2 && abs($0.height - disp.axFrame.height) < 2
					&& abs($0.minX - disp.axFrame.minX) < 2 && abs($0.minY - disp.axFrame.minY) < 2
			} ?? false
			if ownDesktop || covering || saysFull == disp.id { fullNow.insert(disp.id) }
		}
		// Into full screen: step aside at once. Out of it: only once it has stayed
		// that way for 0.15 seconds, as windows pass through in-between sizes on the
		// way and the bar would blink.
		let entering = fullNow.subtracting(hiddenOn)
		let leaving = hiddenOn.subtracting(fullNow)
		if !entering.isEmpty { hiddenOn.formUnion(entering) }
		if leaving.isEmpty {
			showAgainAt = nil
		} else if showAgainAt == nil {
			let when = Date().addingTimeInterval(0.15)
			showAgainAt = when
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(170)) { [weak self] in
				guard let self, self.showAgainAt == when else { return }
				self.refresh()
			}
		} else if let at = showAgainAt, Date() >= at {
			showAgainAt = nil
			hiddenOn.subtract(leaving)
		}
		let mainFull = ds.first.map { hiddenOn.contains($0.id) } ?? false
		if mainFull != fullScreen { fullScreen = mainFull }
	}
}
