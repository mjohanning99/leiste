// The small movements: how badges arrive, how a new window's
// button appears, a hop or a press when a pinned app is clicked and the
// desktop switcher's sliding highlight. Each is a choice in Settings' Motion
// tab and depends on the Motion level there: Full plays everything picked,
// Reduced keeps only gentle fades and slides, Off (or macOS's Reduce Motion)
// moves nothing. Dragging's lift lives in Dragging.swift.
//
// The bar's panel is exactly as tall as the bar, so movements stay within a
// few points of where things are; anything bigger would be cut off.

import SwiftUI

@MainActor
enum Motion {
	private static var prefs: Prefs { Prefs.shared }

	/// How a red badge arrives: popping in with a little overshoot, or fading.
	static var badgeTransition: AnyTransition {
		prefs.playful && prefs.badgeMotion == .pop ? .scale(scale: 0.01).combined(with: .opacity) : .opacity
	}
	static var badgeAnimation: Animation? {
		guard prefs.moves else { return nil }
		return prefs.playful && prefs.badgeMotion == .pop ? .spring(duration: 0.35, bounce: 0.5) : .easeOut(duration: 0.25)
	}

	/// How a new window's button appears: growing from its left edge while the
	/// others slide over, or fading in.
	static var openTransition: AnyTransition {
		guard prefs.playful, prefs.openMotion == .grow else { return .opacity.combined(with: .scale(scale: 0.92)) }
		return .asymmetric(insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
						   removal: .opacity.combined(with: .scale(scale: 0.92)))
	}
	static var rowAnimation: Animation? {
		guard prefs.moves else { return nil }
		return prefs.playful ? .spring(duration: 0.35, bounce: 0.15) : .smooth(duration: 0.25)
	}

	/// Whether the desktop switcher's highlight slides to the new desktop.
	static var slides: Bool { prefs.playful && prefs.switcherMotion == .slide }
	static var switchAnimation: Animation? {
		guard prefs.moves else { return nil }
		return slides ? .spring(duration: 0.3, bounce: 0.15) : .smooth(duration: 0.25)
	}
}

/// A pinned app's answer to a click: how far it is lifted and how far pressed in.
/// (An object rather than @State, which needs Xcode.)
final class Hop: ObservableObject {
	@Published var y: CGFloat = 0
	@Published var scale: CGFloat = 1

	/// Plays the chosen answer to a click, if Motion is at Full.
	@MainActor func play() {
		let prefs = Prefs.shared
		guard prefs.playful else { return }
		switch prefs.clickFeedback {
		case .hop:
			withAnimation(.easeOut(duration: 0.12)) { y = -4 }
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
				withAnimation(.spring(duration: 0.4, bounce: 0.55)) { self.y = 0 }
			}
		case .press:
			withAnimation(.easeOut(duration: 0.08)) { scale = 0.86 }
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(90)) {
				withAnimation(.spring(duration: 0.3, bounce: 0.5)) { self.scale = 1 }
			}
		case .none:
			break
		}
	}
}
