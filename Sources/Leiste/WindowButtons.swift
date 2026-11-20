// The window buttons: the row of this desktop's windows (or groups), what
// sits between them, the red badges and one button with all its states.

import AppKit
import SwiftUI

struct WindowList: View {
	@ObservedObject var model: BarModel
	var display: Display? = nil
	@ObservedObject var prefs = Prefs.shared
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		GeometryReader { geo in
			let tray = prefs.separators == .tray
			let room = geo.size.width - (tray ? 6 : 0)
			let groups = model.groups(width: room, display: display)
			// Every button the same width: 200 points, or less when there are many.
			let count = CGFloat(max(groups.count, 1))
			let width = min(Metrics.windowButtonMax, (room - Metrics.gap * (count - 1)) / count)
			let row = HStack(spacing: Metrics.gap) {
				ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
					// Each button gets only the facts it shows, so SwiftUI can skip the
					// buttons whose facts haven't changed (.equatable()).
					WindowButton(model: model, group: g, width: width, displayID: display?.id ?? model.displays.first?.id ?? 0,
								 elsewhere: elsewhere(g),
								 badge: g.first.bundleID.flatMap { model.badges[$0] },
								 calling: !g.windows.contains(where: \.isActive) && g.first.bundleID.map(model.attention.contains) == true,
								 playing: g.windows.contains(where: { model.isPlaying($0.bundleID) }))
						.equatable()
						// The separator sits in the gap before the button, drawn over it
						// rather than placed in the row, so it takes no room: the row's
						// width is exactly what the sum above expects.
						.overlay(alignment: .leading) {
							if i > 0 { Separator().offset(x: -Metrics.gap / 2 - 0.5) }
						}
						.transition(Motion.openTransition)
				}
			}
			.animation(Motion.rowAnimation, value: groups.map(\.id))
			HStack(spacing: 0) {
				if tray {
					// A sunken tray that holds the windows together.
					row.padding(3)
						.background(scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.05),
									in: RoundedRectangle(cornerRadius: prefs.buttonCorner + 3, style: .continuous))
						.overlay(RoundedRectangle(cornerRadius: prefs.buttonCorner + 3, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
				} else if groups.isEmpty && prefs.emptyText {
					// An empty desktop says so, quietly.
					Text("No windows on this desktop").foregroundStyle(.tertiary).padding(.leading, 6)
						.transition(.opacity)
				} else {
					row
				}
				Spacer(minLength: 0)
			}
			.frame(maxHeight: .infinity)
		}
	}

	/// With every window on every screen's bar, those on another screen are dimmed.
	private func elsewhere(_ g: WindowGroup) -> Bool {
		guard let display, prefs.screens == .all, model.displays.count > 1 else { return false }
		return !g.windows.contains { (model.screenOf[$0.id] ?? model.displays.first?.id) == display.id }
	}
}

/// What sits between two window buttons: drawn over the gap before a button
/// (see WindowList), so it never takes room from the buttons.
struct Separator: View {
	@ObservedObject var prefs = Prefs.shared
	var body: some View {
		switch prefs.separators {
		case .lines:
			Rectangle().fill(.primary.opacity(0.14)).frame(width: 1, height: prefs.buttonHeight * 0.53)
		case .fade:
			Rectangle().fill(LinearGradient(colors: [.clear, .primary.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
				.frame(width: 1, height: prefs.buttonHeight * 0.75)
		case .dots:
			Circle().fill(.primary.opacity(0.3)).frame(width: 3, height: 3).offset(x: -1)
		case .none, .outlines, .tray:
			EmptyView()
		}
	}
}

/// A red badge like the Dock's, with the app's own text ("3", "99+" or a dot).
struct Badge: View {
	let text: String
	var size: CGFloat = 11
	var colour = Color(nsColor: .systemRed)
	var ink = Color.white

	var body: some View {
		Text(text)
			.font(.system(size: size, weight: .semibold).monospacedDigit())
			.foregroundStyle(ink)
			.lineLimit(1)
			.padding(.horizontal, size * 0.4)
			.frame(minWidth: size * 1.6, minHeight: size * 1.6)
			.background(colour, in: Capsule())
			.overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
			.fixedSize()
	}
}

struct WindowButton: View, Equatable {
	/// For its actions only: the button doesn't watch the model, it is handed what it shows.
	let model: BarModel
	let group: WindowGroup
	let width: CGFloat
	/// The screen whose bar it is on, and whether its window is on another screen.
	let displayID: CGDirectDisplayID
	let elsewhere: Bool
	let badge: String?
	let calling: Bool
	let playing: Bool
	@ObservedObject var prefs = Prefs.shared

	/// Redrawn only when what it shows has changed.
	nonisolated static func == (a: WindowButton, b: WindowButton) -> Bool {
		MainActor.assumeIsolated {
			a.group.windows == b.group.windows && a.group.id == b.group.id && a.width == b.width
				&& a.displayID == b.displayID && a.elsewhere == b.elsewhere
				&& a.badge == b.badge && a.calling == b.calling && a.playing == b.playing
		}
	}
	@StateObject private var hover = Hover()
	@StateObject private var drag = DragState()
	@Environment(\.colorScheme) private var scheme

	private var w: BarWindow { group.first }
	private var isGroup: Bool { group.windows.count > 1 }
	private var active: Bool { group.windows.contains { $0.isActive } }
	private var faded: Bool { group.windows.allSatisfy(\.isMinimised) }
	private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: prefs.buttonCorner, style: .continuous) }

	var body: some View {
		Button {
			guard !drag.moved else { return }
			model.click(group)
		} label: {
			// A red badge needs a little more room before the title, so it never touches it.
			HStack(spacing: badge == nil ? 7 : 11) {
				if let icon = w.icon {
					Image(nsImage: icon).resizable().frame(width: prefs.windowIcon, height: prefs.windowIcon)
						.opacity(faded ? 0.45 : 1)
						.overlay(alignment: .topTrailing) {
							if let badge { Badge(text: badge, size: 9.5).offset(x: 6, y: -6).transition(Motion.badgeTransition) }
						}
						.animation(Motion.badgeAnimation, value: badge)
						.overlay(alignment: .bottomTrailing) {
							// A group says so: how many windows share the button, in grey, where the red badge isn't.
							if isGroup {
								Badge(text: "\(group.windows.count)", size: 9, colour: Color(nsColor: .labelColor).opacity(0.78),
									  ink: Color(nsColor: .windowBackgroundColor)).offset(x: 6, y: 5)
							}
						}
				}
				Text(isGroup ? w.appName : w.title)
					.fontWeight(active ? .semibold : .regular)
					.foregroundStyle(faded ? .secondary : .primary)
					.lineLimit(1).truncationMode(.tail)
				Spacer(minLength: 0)
				if prefs.sound, playing {
					Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(.secondary)
				}
			}
			.padding(.leading, prefs.shape == .capsule ? 9 : 7).padding(.trailing, 10)
			.frame(width: width, height: prefs.buttonHeight)
			.background(fill, in: shape)
			.shadow(color: .black.opacity(active && prefs.front == .raised ? (scheme == .dark ? 0.35 : 0.14) : 0), radius: 1.5, y: 1)
			.overlay {
				if (active && prefs.front != .line) || prefs.separators == .outlines {
					shape.strokeBorder(.primary.opacity(active ? 0.10 : 0.12), lineWidth: 0.5)
				}
			}
			// The window in front as a line underneath, like a tab.
			.overlay(alignment: .bottom) {
				if active && prefs.front == .line {
					Capsule().fill(Color.accentColor).frame(width: width * 0.4, height: 3).padding(.bottom, 1)
				}
			}
			// A group can look like a small stack: the edge of a second button peeks
			// out behind it (Look → "Groups look like a stack"; off by default, as
			// the grey count already says it's a group).
			.background {
				if isGroup && prefs.groupStack {
					shape.strokeBorder(.primary.opacity(0.16), lineWidth: 0.5)
						.background(.primary.opacity(0.04), in: shape)
						.offset(x: 2.5, y: -2.5)
				}
			}
			.swell(hover.on && prefs.pointing == .swell && !active, corner: prefs.buttonCorner)
			.opacity(elsewhere ? 0.55 : 1)
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { on in
			hover.on = on
			if on { model.pointedApp = w.bundleID } else if model.pointedApp == w.bundleID { model.pointedApp = nil }
		}
		.help(isGroup ? group.windows.map(\.title).joined(separator: "\n") : w.title)
		// What VoiceOver says: the window, its app and its state.
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(spoken)
		.accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
		.accessibilityHint(Text(isGroup ? LocalizedStringKey("Brings the next of its windows forward") : (active ? LocalizedStringKey("Minimises it") : LocalizedStringKey("Brings it forward"))))
		// Where the button is, so a window minimised into Leiste can fly to it.
		.background {
			GeometryReader { g in
				Color.clear
					.onAppear { remember(g.frame(in: .global)) }
					.onChange(of: g.frame(in: .global)) { _, f in remember(f) }
			}
		}
		.contextMenu { WindowMenu(model: model, group: group) }
		.draggable(drag, step: width + Metrics.gap,
				   over: { model.desktopNumber(at: $0, display: displayID) },
				   dropped: { model.dropOnDesktop(group) }) { steps in
			model.move(group, by: steps, among: model.shownGroups)
		}
		.animation(.easeOut(duration: 0.25), value: calling)
	}

	/// "Safari, Swift documentation, in front, playing sound" or "iTerm, 3 windows".
	private var spoken: String {
		var parts = [w.appName]
		if isGroup { parts.append(String(localized: "\(group.windows.count) windows")) } else if w.title != w.appName { parts.append(w.title) }
		if active { parts.append(String(localized: "in front")) }
		if faded { parts.append(String(localized: "minimised")) }
		if calling { parts.append(String(localized: "asking for attention")) }
		if prefs.sound, playing { parts.append(String(localized: "playing sound")) }
		if let badge { parts.append(String(localized: "badge \(badge)")) }
		return parts.joined(separator: ", ")
	}

	private func remember(_ frame: CGRect) {
		for gw in group.windows { model.buttonFrames[gw.id] = (displayID, frame) }
	}

	// The window in front stands out (fill, raised or accent); a window asking
	// for you glows a soft orange (as in Plasma); pointing at one tints it lightly.
	private var fill: Color {
		if active {
			switch prefs.front {
			case .fill, .raised: return ActiveFill.color(scheme)
			case .accent: return Color.accentColor.opacity(scheme == .dark ? 0.28 : 0.18)
			case .line: return hover.on ? .primary.opacity(0.07) : .clear
			}
		}
		if calling { return Color(nsColor: .systemOrange).opacity(scheme == .dark ? 0.32 : 0.28) }
		let pointed = hover.on || drag.x != 0
		if prefs.separators == .outlines { return pointed ? .primary.opacity(0.08) : .primary.opacity(0.03) }
		return pointed ? .primary.opacity(0.07) : .clear
	}
}
