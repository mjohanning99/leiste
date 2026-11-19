// The desktop switcher at the right end, in four styles: numbers, a segmented
// switch, dots or little pictures of each desktop. The scroll wheel over it
// moves between desktops. The highlight slides to the new desktop (Motion →
// "Switching desktops"), and a number lights up while a window's button is
// dragged over it, to be dropped there.

import AppKit
import SwiftUI

struct DesktopSwitcher: View {
	@ObservedObject var model: BarModel
	var display: Display? = nil
	@ObservedObject var prefs = Prefs.shared
	@Environment(\.colorScheme) private var scheme
	/// Lets the highlight be one thing that slides from number to number.
	@Namespace private var highlight

	var body: some View {
		Group {
			switch prefs.desktopStyle {
			case .numbers: numbers
			case .segmented: segmented
			case .dots: dots
			case .pictures: pictures
			}
		}
		// The scroll wheel over the switcher moves between desktops.
		.onHover { on in
			model.overDesktops = on
			model.overDesktopsDisplay = on ? display?.id : nil
		}
		.animation(Motion.switchAnimation, value: info.current)
		.animation(prefs.moves ? .spring(duration: 0.25, bounce: 0.4) : nil, value: model.dropTarget?.desktop)
	}

	private var displayID: CGDirectDisplayID { display?.id ?? model.displays.first?.id ?? 0 }
	/// Whether a window's button is being dragged over desktop `n`.
	private func lit(_ n: Int) -> Bool { model.dropTarget?.desktop == n && model.dropTarget?.display == displayID }

	/// This screen's desktops (screens can have their own, or share one set).
	private var info: DesktopInfo { display.flatMap { model.desktopsOn[$0.id] } ?? model.desktops }
	private var range: [Int] { Array(1...info.count) }
	private func on(_ n: Int) -> Bool { n == info.current }

	/// Separate buttons, the same height and corners as the window buttons.
	private var numbers: some View {
		HStack(spacing: 4) {
			ForEach(range, id: \.self) { n in
				let shape = RoundedRectangle(cornerRadius: prefs.buttonCorner, style: .continuous)
				Button { model.goToDesktop(n, on: display) } label: {
					Text("\(n)")
						.font(.system(size: 12, weight: on(n) ? .semibold : .medium).monospacedDigit())
						.foregroundStyle(on(n) ? .primary : .secondary)
						.frame(minWidth: prefs.shape == .capsule ? 34 : 30, minHeight: prefs.buttonHeight)
						.background {
							if on(n) {
								shape.fill(ActiveFill.color(scheme))
									.overlay { shape.strokeBorder(.primary.opacity(0.10), lineWidth: 0.5) }
									.modifier(Slides(id: "number", in: highlight))
							}
						}
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.modifier(DropSpot(model: model, display: displayID, n: n, lit: lit(n)))
				.help("Desktop \(n)")
				.accessibilityLabel("Desktop \(n)")
				.accessibilityAddTraits(on(n) ? [.isButton, .isSelected] : .isButton)
			}
		}
	}

	/// One sunken track with the current desktop raised, like macOS's segmented controls.
	private var segmented: some View {
		let h = prefs.buttonHeight - 4
		let corner = prefs.shape == .capsule ? h / 2 : 8
		return HStack(spacing: 0) {
			ForEach(range, id: \.self) { n in
				Button { model.goToDesktop(n, on: display) } label: {
					Text("\(n)")
						.font(.system(size: 12, weight: on(n) ? .semibold : .medium).monospacedDigit())
						.foregroundStyle(on(n) ? .primary : .secondary)
						.frame(minWidth: 32, minHeight: h - 6)
						.background {
							if on(n) {
								RoundedRectangle(cornerRadius: corner - 3, style: .continuous).fill(ActiveFill.color(scheme))
									.shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 1.5, y: 1)
									.modifier(Slides(id: "segment", in: highlight))
							}
						}
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.modifier(DropSpot(model: model, display: displayID, n: n, lit: lit(n)))
				.help("Desktop \(n)")
				.accessibilityLabel("Desktop \(n)")
				.accessibilityAddTraits(on(n) ? [.isButton, .isSelected] : .isButton)
			}
		}
		.padding(3)
		.background(scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.06),
					in: RoundedRectangle(cornerRadius: corner, style: .continuous))
	}

	/// Dots like the pages on an iPhone; the current desktop is a longer bar.
	private var dots: some View {
		HStack(spacing: 8) {
			ForEach(range, id: \.self) { n in
				Button { model.goToDesktop(n, on: display) } label: {
					Capsule().fill(on(n) ? Color.primary : Color.primary.opacity(0.35))
						.frame(width: on(n) ? 22 : 8, height: 8)
						.padding(.vertical, 10)
						.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.modifier(DropSpot(model: model, display: displayID, n: n, lit: lit(n)))
				.help("Desktop \(n)")
				.accessibilityLabel("Desktop \(n)")
				.accessibilityAddTraits(on(n) ? [.isButton, .isSelected] : .isButton)
			}
		}
		.padding(.horizontal, 6)
	}

	/// Little pictures of each desktop with outlines of its windows; the current one ringed in the accent colour.
	private var pictures: some View {
		let h = prefs.buttonHeight - 4
		let w = (h * 1.5).rounded()
		return HStack(spacing: 6) {
			ForEach(range, id: \.self) { n in
				Button { model.goToDesktop(n, on: display) } label: {
					ZStack(alignment: .topLeading) {
						RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.06))
						ForEach(Array((model.desktopPictures[n] ?? []).prefix(8).enumerated()), id: \.offset) { _, r in
							RoundedRectangle(cornerRadius: 1.5).fill(.primary.opacity(0.3))
								.frame(width: max(3, r.width * w), height: max(2, r.height * h))
								.offset(x: r.minX * w, y: r.minY * h)
						}
						Text("\(n)").font(.system(size: 9, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 3)
					}
					.frame(width: w, height: h)
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
					.overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
						.strokeBorder(on(n) ? Color.accentColor : .primary.opacity(0.12), lineWidth: on(n) ? 1.5 : 0.5))
					.contentShape(.rect)
				}
				.buttonStyle(.plain)
				.modifier(DropSpot(model: model, display: displayID, n: n, lit: lit(n)))
				.help("Desktop \(n)")
				.accessibilityLabel("Desktop \(n)")
				.accessibilityAddTraits(on(n) ? [.isButton, .isSelected] : .isButton)
			}
		}
	}
}

/// Makes the highlight one shape that slides between numbers, when Motion is
/// at Full and "Switching desktops" slides; otherwise it simply moves.
private struct Slides: ViewModifier {
	let id: String
	let `in`: Namespace.ID
	func body(content: Content) -> some View {
		if Motion.slides { content.matchedGeometryEffect(id: id, in: `in`) } else { content }
	}
}

/// A desktop button as a place to drop a window's button: it tells the model
/// where it is, and lights up and swells while something is dragged over it.
private struct DropSpot: ViewModifier {
	let model: BarModel
	let display: CGDirectDisplayID
	let n: Int
	let lit: Bool
	func body(content: Content) -> some View {
		content
			.background {
				if lit { Capsule().fill(Color.accentColor.opacity(0.28)).padding(-2) }
			}
			.scaleEffect(lit && Prefs.shared.moves ? 1.18 : 1)
			.background {
				GeometryReader { g in
					Color.clear
						.onAppear { model.desktopFrames[display, default: [:]][n] = g.frame(in: .global) }
						.onChange(of: g.frame(in: .global)) { _, f in model.desktopFrames[display, default: [:]][n] = f }
				}
			}
	}
}
