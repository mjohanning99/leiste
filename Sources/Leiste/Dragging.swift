// Dragging buttons to a new place, the swell under the pointer and whether
// the pointer is over a button.
//
// While a button is dragged it lifts out of the bar (a touch larger, raised,
// with a soft shadow, leaning into the move: Motion → "Dragging a button")
// and the others make room as it passes them: the order changes as you drag,
// not only when you let go. A window's button can also be dropped onto a
// desktop number (see Clicks.swift).

import AppKit
import SwiftUI

/// A button being dragged. (An object rather than @State, which needs Xcode.)
final class DragState: ObservableObject {
	/// How far the button sits from its place, following the pointer.
	@Published var x: CGFloat = 0
	@Published var active = false
	/// The lean, in degrees, from how fast it is moving.
	@Published var tilt: Double = 0
	/// Dropped onto a desktop number: it shrinks away into it.
	@Published var flying = false
	/// Set while dragging, so letting go doesn't also count as a click.
	var moved = false
	/// How much of the drag has already become places moved.
	var consumed: CGFloat = 0
	var overTarget = false
}

extension View {
	/// Lets a button be dragged sideways. `move` is asked to move it some places
	/// along and says how many it really moved. `over` (optional) says whether
	/// the pointer, in the bar's coordinates, is over somewhere to drop it;
	/// `dropped` is then called when it is let go there.
	func draggable(_ drag: DragState, step: CGFloat,
				   over: ((CGPoint) -> Bool)? = nil, dropped: (() -> Void)? = nil,
				   move: @escaping (Int) -> Int) -> some View {
		let prefs = Prefs.shared
		let lift = drag.active && prefs.playful && prefs.dragStyle != .none
		return self
			.scaleEffect(drag.flying ? 0.15 : (lift ? 1.06 : 1))
			.shadow(color: .black.opacity(lift ? 0.22 : 0), radius: lift ? 5 : 0, y: lift ? 2 : 0)
			.rotationEffect(.degrees(lift && prefs.dragStyle == .lift ? drag.tilt : 0))
			.animation(lift ? .spring(duration: 0.3) : nil, value: drag.tilt)
			.opacity(drag.flying ? 0 : 1)
			.offset(x: drag.x, y: lift ? -2 : 0)
			.animation(prefs.moves ? .spring(duration: 0.25, bounce: 0.3) : nil, value: lift)
			.zIndex(drag.active || drag.flying ? 1 : 0)
			// While dragged, it follows the pointer exactly: the bar's own slide
			// as the others make room mustn't move it too.
			.transaction { t in if drag.active { t.animation = nil } }
			.simultaneousGesture(
				// In the bar's coordinates, which don't shift as the button moves.
				DragGesture(minimumDistance: 6, coordinateSpace: .global)
					.onChanged { value in
						drag.moved = true
						if !drag.active { drag.active = true }
						let t = value.translation.width
						drag.overTarget = over?(value.location) ?? false
						// Passed half a button: it takes the next place, and the others slide over.
						if !drag.overTarget {
							let steps = Int(((t - drag.consumed) / step).rounded())
							if steps != 0 { drag.consumed += CGFloat(move(steps)) * step }
						}
						drag.x = t - drag.consumed
						drag.tilt = max(-2, min(2, value.velocity.width / 400))
					}
					.onEnded { _ in
						let drop = drag.overTarget && dropped != nil
						drag.overTarget = false
						drag.consumed = 0
						if drop {
							// It flies into the number, then the window follows (that takes
							// about a second); it comes back only if the window didn't go.
							withAnimation(prefs.moves ? .easeIn(duration: 0.2) : nil) { drag.flying = true }
							drag.active = false
							dropped?()
							DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
								drag.flying = false; drag.x = 0; drag.tilt = 0
							}
						} else {
							withAnimation(prefs.moves ? .spring(duration: 0.3, bounce: 0.25) : nil) {
								drag.x = 0; drag.tilt = 0; drag.active = false
							}
						}
						// The button sees the mouse go up too; this stops that counting as a click.
						DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { drag.moved = false }
					}
			)
	}

	/// The swell under the pointer: a touch larger, with an edge.
	func swell(_ on: Bool, corner: CGFloat) -> some View {
		self
			.scaleEffect(on && Prefs.shared.moves ? 1.05 : 1)
			.overlay {
				if on { RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
			}
			.animation(Prefs.shared.moves ? .spring(duration: 0.2) : nil, value: on)
	}
}

/// Whether the pointer is over a button. (A small object rather than @State,
/// because @State needs a compiler plug-in that comes only with Xcode.)
final class Hover: ObservableObject {
	@Published var on = false
}
