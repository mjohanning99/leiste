// How the bar looks. By default it is a floating Liquid Glass bar in three
// islands (launchers, windows, desktops), with a bright rim, the window in
// front raised, fading lines between windows and a segmented desktop
// switcher; every other look is a choice in Settings. It uses the
// system's own glass, typeface and colours, so it follows light and dark
// mode by itself.

import AppKit
import SwiftUI

enum Metrics {
	static let inset: CGFloat = 8	// the gap to the screen's edges
	static let windowButtonMax: CGFloat = 200
	static let gap: CGFloat = 3	// between buttons
	static let islandGap: CGFloat = 8	// between islands
}

/// The fill of the button you're working in, the same everywhere on the bar.
enum ActiveFill {
	static func color(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white.opacity(0.16) : .white.opacity(0.72) }
}

struct BarView: View {
	@ObservedObject var model: BarModel
	/// The screen this bar is on (nil in pictures: the main one).
	var display: Display? = nil
	@ObservedObject var prefs = Prefs.shared

	var body: some View {
		Group {
			if prefs.islands {
				// Three pieces of glass: launchers, windows, desktops.
				HStack(spacing: Metrics.islandGap) {
					Launchers(model: model).padding(.horizontal, 8).frame(maxHeight: .infinity).modifier(Glass(prefs: prefs))
					Windows(model: model, display: display).padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(Glass(prefs: prefs))
					if desktops.count > 1 {
						DesktopSwitcher(model: model, display: display).padding(.horizontal, 8).frame(maxHeight: .infinity).modifier(Glass(prefs: prefs))
					}
				}
			} else {
				HStack(spacing: Metrics.gap) {
					Launchers(model: model)
					Divider().frame(height: prefs.height - 20).padding(.horizontal, 4)
					Windows(model: model, display: display)
					if desktops.count > 1 {
						DesktopSwitcher(model: model, display: display).padding(.leading, 6)
					}
				}
				.padding(.horizontal, prefs.shape == .capsule && prefs.position == .floating ? 12 : 8)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.modifier(Glass(prefs: prefs))
			}
		}
		.contentShape(.rect)
		.contextMenu { BarMenu() }
		.font(.system(size: prefs.fontSize))
	}

	/// This screen's desktops (screens can have their own, or share one set).
	private var desktops: DesktopInfo { display.flatMap { model.desktopsOn[$0.id] } ?? model.desktops }
}

struct Launchers: View {
	@ObservedObject var model: BarModel
	var body: some View {
		HStack(spacing: 2) {
			ForEach(model.launchers) { l in
				// Only the facts it shows, so unchanged launchers are skipped when the bar redraws.
				LauncherButton(model: model, launcher: l, badge: model.badges[l.id],
							   calling: model.attention.contains(l.id) && !model.windows.contains { $0.bundleID == l.id },
							   running: model.running.contains(l.id))
					.equatable()
			}
		}
		.animation(Prefs.shared.moves ? .smooth(duration: 0.25) : nil, value: model.launchers.map(\.id))
	}
}

struct Windows: View {
	@ObservedObject var model: BarModel
	var display: Display? = nil
	var body: some View {
		if model.trusted {
			WindowList(model: model, display: display)
		} else {
			// Without the permission, a clear line and a button that opens the right page.
			HStack(spacing: 8) {
				Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size: 15))
				Text("Leiste can\u{2019}t see your windows. It needs the Accessibility permission.")
					.lineLimit(1).truncationMode(.tail)
				Spacer(minLength: 0)
				Button("Open Settings") {
					NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
				}
				.buttonStyle(.borderedProminent).controlSize(.small)
			}
			.padding(.leading, 4)
		}
	}
}

/// The system's Liquid Glass (macOS 26 and later), clear or frosted, with as
/// much solid colour over it as the "See-through" slider asks for and the
/// edge chosen in Settings.
struct Glass: ViewModifier {
	@ObservedObject var prefs: Prefs
	@Environment(\.colorScheme) private var scheme
	/// Set for --snapshot: glass draws nothing in a picture, so use a plain fill there.
	nonisolated(unsafe) static var plain = false

	func body(content: Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: prefs.barCorner, style: .continuous)
		let solid = content.background(Color(nsColor: .windowBackgroundColor).opacity(prefs.solidity), in: shape)
		Group {
			if Glass.plain {
				solid.background(Color.primary.opacity(0.06), in: shape)
			} else if #available(macOS 26.0, *) {
				solid.glassEffect(prefs.glass == .clear ? .clear : .regular, in: shape)
			} else {
				solid.background(.regularMaterial, in: shape)
			}
		}
		.overlay { edge(shape) }
		// Along the edge, a hairline on top separates the bar from the windows above.
		.overlay(alignment: .top) {
			if prefs.position == .edge { Rectangle().fill(.primary.opacity(0.12)).frame(height: 0.5) }
		}
	}

	/// The light along the rim: brightest at the top left and the bottom right,
	/// as on the Dock. "Rim and glow" adds a little light inside the top edge.
	@ViewBuilder private func edge(_ shape: RoundedRectangle) -> some View {
		let bright = scheme == .dark ? 0.45 : 0.95
		let low = scheme == .dark ? 0.05 : 0.15
		switch prefs.edge {
		case .line:
			shape.strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
		case .rim, .glow:
			ZStack {
				shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(bright), location: 0),
														  .init(color: .white.opacity(low), location: 0.35),
														  .init(color: .white.opacity(low), location: 0.65),
														  .init(color: .white.opacity(bright), location: 1)],
												  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
				if prefs.edge == .glow {
					shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.08 : 0.22), .clear],
											  startPoint: .top, endPoint: .center))
				}
			}
			.allowsHitTesting(false)
		}
	}
}
