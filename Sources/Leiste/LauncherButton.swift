// A pinned app's button: its icon, badge and running dot, a click to open a
// new window here, and its right-click menu.

import AppKit
import SwiftUI

struct LauncherButton: View, Equatable {
	/// For its actions only: the button doesn't watch the model, it is handed what it shows.
	let model: BarModel
	let launcher: Launcher
	let badge: String?
	let calling: Bool
	let running: Bool
	@ObservedObject var prefs = Prefs.shared

	/// Redrawn only when what it shows has changed.
	nonisolated static func == (a: LauncherButton, b: LauncherButton) -> Bool {
		MainActor.assumeIsolated {
			a.launcher.id == b.launcher.id && a.badge == b.badge && a.calling == b.calling && a.running == b.running
		}
	}
	@StateObject private var hover = Hover()
	@StateObject private var drag = DragState()
	@StateObject private var hop = Hop()
	@Environment(\.colorScheme) private var scheme

	private var step: CGFloat { prefs.launcherIcon + 8 }

	var body: some View {
		Button {
			guard !drag.moved else { return }
			hop.play()
			model.launch(launcher)
		} label: {
			Image(nsImage: launcher.icon).resizable().frame(width: prefs.launcherIcon, height: prefs.launcherIcon)
				.overlay(alignment: .topTrailing) {
					if let badge { Badge(text: badge).offset(x: 6, y: -4).transition(Motion.badgeTransition) }
				}
				.animation(Motion.badgeAnimation, value: badge)
				.scaleEffect(hop.scale)
				.offset(y: hop.y)
				.padding(3)
				.background(background, in: RoundedRectangle(cornerRadius: prefs.buttonCorner, style: .continuous))
				// A dot under a pinned app that is open, as the Dock shows.
				.overlay(alignment: .bottom) {
					if prefs.runningDots, running {
						Circle().fill(.primary.opacity(0.6)).frame(width: 4, height: 4).offset(y: 3)
					}
				}
				.swell(hover.on && prefs.pointing == .swell, corner: prefs.buttonCorner)
		}
		.buttonStyle(.plain)
		.onHover { on in
			hover.on = on
			if on { model.pointedApp = launcher.id } else if model.pointedApp == launcher.id { model.pointedApp = nil }
		}
		.help("New \(launcher.name) window")
		.accessibilityElement(children: .ignore)
		.accessibilityLabel([launcher.name, running ? String(localized: "open") : nil, calling ? String(localized: "asking for attention") : nil,
							 badge.map { String(localized: "badge \($0)") }]
			.compactMap { $0 }.joined(separator: ", "))
		.accessibilityAddTraits(.isButton)
		.accessibilityHint("Opens a new \(launcher.name) window on this desktop")
		.contextMenu {
			Button { model.launch(launcher) } label: { ItemLabel("New \(launcher.name) Window", "macwindow.badge.plus") }
			Divider()
			AppMenu(model: model, bundleID: launcher.id, name: launcher.name)
			if model.isRunning(launcher.id) {
				Button { model.quit(launcher.id) } label: { ItemLabel("Quit \(launcher.name)", "power") }
			}
			Divider()
			BarMenu()
		}
		.draggable(drag, step: step) { steps in model.moveLauncher(launcher.id, by: steps) }
	}

	// An app asking for you with no window here: its launcher glows instead.
	private var background: Color {
		if calling { return Color(nsColor: .systemOrange).opacity(scheme == .dark ? 0.32 : 0.28) }
		return (hover.on && prefs.pointing == .tint) || drag.x != 0 ? .primary.opacity(0.07) : .clear
	}
}
