// What opens above a button when the pointer rests on it: a group's windows
// as a list to pick from, or a single window's full title when its button
// cuts it short (Settings → Windows). Titles only, never pictures of windows,
// so no Screen Recording.
//
// It opens after a short wait (so crossing the bar doesn't flash it open),
// switches at once from one button to the next while open, and closes a
// moment after the pointer has left both the button and the list, so the
// pointer can travel to a row.

import AppKit
import SwiftUI

/// The panel the list sits in: above the bar, never taking the keyboard.
final class HoverPanel: NSPanel {
	init() {
		super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		isOpaque = false
		backgroundColor = .clear
		hasShadow = false	// drawn by the view, so it follows the rounded glass
		level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
		collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		isMovable = false
		hidesOnDeactivate = false
	}
	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}

@MainActor
final class HoverList {
	static let shared = HoverList()

	private var panel: HoverPanel?
	/// The button whose list (or title) is showing, and the one waiting to open.
	private(set) var shown: String?
	private var pending: String?
	private var openWork: DispatchWorkItem?
	private var closeWork: DispatchWorkItem?
	private var overPanel = false
	private var closedAt = Date.distantPast
	/// The room the view leaves around the glass for its shadow.
	static let margin: CGFloat = 14
	/// The widest the glass gets; longer titles are shortened in the middle.
	static let widestGlass: CGFloat = 400
	static var widest: CGFloat { widestGlass + 2 * margin }

	private init() {
		// A right-click menu opening puts the list away.
		NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
			MainActor.assumeIsolated { HoverList.shared.hide() }
		}
	}

	/// The pointer came onto a button. `key` names the button, `anchor` is the
	/// stretch of screen (AppKit coordinates) to centre over: the button's left
	/// and right, and the bar's top.
	func enter(_ key: String, anchor: CGRect, interactive: Bool, content: @escaping () -> AnyView) {
		closeWork?.cancel()
		if shown == key { return }
		openWork?.cancel()
		pending = key
		let open = { [weak self] in
			guard let self, self.pending == key else { return }
			self.pending = nil
			self.show(key, anchor: anchor, interactive: interactive, content: content())
		}
		// Already open (or just closed): move straight over, as menus do.
		let delay = (shown != nil || Date().timeIntervalSince(closedAt) < 0.3) ? 0 : Prefs.shared.listDelay.seconds
		if delay == 0 { open(); return }
		let work = DispatchWorkItem(block: open)
		openWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	/// The pointer left a button.
	func leave(_ key: String) {
		if pending == key { openWork?.cancel(); pending = nil }
		guard shown == key else { return }
		closeSoon()
	}

	/// The pointer came onto or left the list itself.
	func pointerInList(_ on: Bool) {
		overPanel = on
		if on { closeWork?.cancel() } else { closeSoon() }
	}

	/// Puts it away at once (a click, a drag, a menu, the bar stepping aside).
	func hide() {
		openWork?.cancel(); closeWork?.cancel()
		pending = nil
		guard shown != nil else { return }
		shown = nil
		overPanel = false
		closedAt = Date()
		panel?.orderOut(nil)
		panel?.contentView = nil
	}

	private func closeSoon() {
		closeWork?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self, !self.overPanel else { return }
			self.hide()
		}
		closeWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	private func show(_ key: String, anchor: CGRect, interactive: Bool, content: AnyView) {
		let p = panel ?? HoverPanel()
		panel = p
		overPanel = false
		let host = FirstClickHostingView(rootView: content)
		p.contentView = host
		p.ignoresMouseEvents = !interactive
		// As wide as it wants, up to what the view allows: offered no width,
		// SwiftUI would draw long titles past the glass, so it is offered its own.
		let probe = NSHostingController(rootView: content)
		let wide = probe.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
		let size = probe.sizeThatFits(in: CGSize(width: min(wide.width, Self.widest), height: .greatestFiniteMagnitude))
		// Centred over the button, its glass 6 points above the bar, kept on the screen.
		let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.frame ?? NSScreen.main?.frame ?? .zero
		var x = anchor.midX - size.width / 2
		x = min(max(x, screen.minX + Metrics.inset - Self.margin), screen.maxX - Metrics.inset + Self.margin - size.width)
		p.setFrame(NSRect(x: x, y: anchor.maxY + 6 - Self.margin, width: size.width, height: size.height), display: true)
		let fresh = shown == nil
		shown = key
		if fresh && Prefs.shared.moves {
			p.alphaValue = 0
			p.orderFrontRegardless()
			NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; p.animator().alphaValue = 1 }
		} else {
			p.alphaValue = 1
			p.orderFrontRegardless()
		}
	}

	/// Where a button is on screen, for `enter`: its left and right, and the top of its bar.
	static func anchor(ofButton id: CGWindowID, in model: BarModel) -> CGRect? {
		guard let b = model.buttonFrames[id], let p = BarModel.panelFrames[b.display] else { return nil }
		return CGRect(x: p.minX + b.frame.minX, y: p.minY, width: b.frame.width, height: p.height)
	}
}

/// The glass behind the list and the title: the system's own, a plain fill in pictures.
private struct PopGlass: ViewModifier {
	@Environment(\.colorScheme) private var scheme
	let corner: CGFloat
	func body(content: Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
		Group {
			if Glass.plain {
				content.background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: shape)
			} else if #available(macOS 26.0, *) {
				content.glassEffect(.regular, in: shape)
			} else {
				content.background(.regularMaterial, in: shape)
			}
		}
		.overlay(shape.strokeBorder(.primary.opacity(scheme == .dark ? 0.16 : 0.10), lineWidth: 0.5))
		.shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 9, y: 3)
		.padding(HoverList.margin)
	}
}

/// A group's windows, the one in front ticked. A click brings that window forward
/// (a minimised or tucked-away one comes back first).
struct GroupList: View {
	@ObservedObject var model: BarModel
	let ids: [CGWindowID]
	@ObservedObject var prefs = Prefs.shared

	var body: some View {
		// The windows as they are now, so a new title or a closed window shows at once.
		let windows = ids.compactMap { id in model.windows.first { $0.id == id } }
		VStack(alignment: .leading, spacing: 0) {
			if let w = windows.first {
				HStack(spacing: 7) {
					if let icon = w.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
					Text("\(w.appName) · \(windows.count) windows")
				}
				.font(.system(size: prefs.fontSize - 1.5, weight: .semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 9).padding(.top, 5).padding(.bottom, 6)
				.accessibilityAddTraits(.isHeader)
			}
			ForEach(windows) { w in
				GroupListRow(model: model, window: w, tucked: model.tucked[w.id] != nil)
			}
		}
		.padding(6)
		.frame(minWidth: 220, maxWidth: HoverList.widestGlass, alignment: .leading)
		.modifier(PopGlass(corner: 16))
		.font(.system(size: prefs.fontSize))
		.onHover { HoverList.shared.pointerInList($0) }
		.onChange(of: windows.isEmpty) { _, empty in if empty { HoverList.shared.hide() } }
	}
}

private struct GroupListRow: View {
	let model: BarModel
	let window: BarWindow
	let tucked: Bool
	@StateObject private var hover = Hover()

	var body: some View {
		Button {
			HoverList.shared.hide()
			model.raise(window)
		} label: {
			HStack(spacing: 8) {
				Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
					.foregroundStyle(hover.on ? Color.white : Color.accentColor)
					.opacity(window.isActive ? 1 : 0)
					.frame(width: 14)
				Text(window.title.isEmpty ? window.appName : window.title)
					.fontWeight(window.isActive ? .semibold : .regular)
					.italic(window.isMinimised)
					.foregroundStyle(hover.on ? AnyShapeStyle(.white) : (window.isMinimised ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)))
					.lineLimit(1).truncationMode(.middle)
				Spacer(minLength: 8)
				if window.isMinimised {
					Text(tucked ? LocalizedStringKey("tucked away") : LocalizedStringKey("minimised"))
						.font(.system(size: 11))
						.foregroundStyle(hover.on ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
				}
			}
			.padding(.horizontal, 9)
			.frame(height: 30)
			.background(hover.on ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.onHover { hover.on = $0 }
		.accessibilityLabel(window.title)
		.accessibilityValue(Text(window.isActive ? LocalizedStringKey("in front") : (window.isMinimised ? (tucked ? LocalizedStringKey("tucked away") : LocalizedStringKey("minimised")) : LocalizedStringKey(""))))
	}
}

/// A single window's whole title, when its button has to cut it short.
struct FullTitle: View {
	let title: String
	let app: String
	@ObservedObject var prefs = Prefs.shared

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(title).lineLimit(1).truncationMode(.middle)
			if app != title { Text(app).font(.system(size: prefs.fontSize - 2)).foregroundStyle(.secondary) }
		}
		.font(.system(size: prefs.fontSize - 0.5))
		.padding(.horizontal, 12).padding(.vertical, 7)
		.frame(maxWidth: HoverList.widestGlass, alignment: .leading)
		.modifier(PopGlass(corner: 11))
	}
}
