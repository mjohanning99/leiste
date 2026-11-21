// Leiste's options, as chosen in the Settings window. They are kept in
// ~/Library/Application Support/Leiste/options.txt ("name = value" lines),
// so they can be read and changed by hand too.

import AppKit
import ServiceManagement
import SwiftUI

enum GlassKind: String, CaseIterable { case clear, frosted }
enum BarShape: String, CaseIterable { case rounded, capsule }
/// What separates one window's button from the next.
enum Separators: String, CaseIterable { case none, lines, fade, dots, outlines, tray }
enum Position: String, CaseIterable { case floating, edge }
/// How much moves: everything picked (full), only gentle fades (reduced), or nothing.
/// macOS's own Reduce Motion always counts as off.
enum MotionLevel: String, CaseIterable { case full, reduced, off }
/// The small movements, each a choice of its own.
enum DragStyle: String, CaseIterable { case lift, flat, none }
enum SwitcherMotion: String, CaseIterable { case slide, jump }
enum BadgeMotion: String, CaseIterable { case pop, fade }
enum OpenMotion: String, CaseIterable { case grow, fade }
enum ClickFeedback: String, CaseIterable { case hop, press, none }
/// Which screens get a bar: each its own windows, each every window, or the main screen only.
enum ScreenChoice: String, CaseIterable { case each, all, main }
/// Where a minimised window goes: into the Dock (macOS's own minimise) or into Leiste (Tuck.swift).
enum MinimiseInto: String, CaseIterable { case dock, leiste }
/// What flies into the bar instead of the window (Ghost.swift).
enum StandIn: String, CaseIterable { case outline, glass }
/// How it flies: shrinking in one piece, or pouring in like Plasma's magic lamp.
enum GhostMotion: String, CaseIterable { case lamp, squash }
/// One strip of glass, or three islands: launchers, windows and desktops.
enum Layout: String, CaseIterable { case one, islands }
/// The light along the glass's edge.
enum Edge: String, CaseIterable { case line, rim, glow }
/// How the window in front stands out.
enum FrontStyle: String, CaseIterable { case fill, raised, accent, line }
/// The desktop switcher.
enum DesktopStyle: String, CaseIterable { case numbers, segmented, dots, pictures }
/// What happens under the pointer.
enum PointStyle: String, CaseIterable { case tint, swell }
/// How long the pointer rests on a button before its list or full title opens.
enum ListDelay: String, CaseIterable {
	case now, short, long
	var seconds: Double { [.now: 0, .short: 0.4, .long: 0.8][self]! }
}
/// How tall the bar is.
enum BarSize: String, CaseIterable {
	case compact, standard, large
	var height: CGFloat { [.compact: 40, .standard: 46, .large: 54][self]! }
}

@MainActor
final class Prefs: ObservableObject {
	static let shared = Prefs()
	/// Off while drawing pictures (--snapshot), so they don't change your settings.
	var persist = true

	@Published var grouping: Grouping { didSet { save("grouping", grouping.rawValue) } }
	@Published var glass: GlassKind { didSet { save("glass", glass.rawValue) } }
	/// 0 is the see-through glass alone; 0.9 is nearly solid.
	@Published var solidity: Double { didSet { save("solidity", String(format: "%.2f", solidity)) } }
	/// Floating a little above the bottom (the default) or along the very edge, like a Plasma panel.
	@Published var position: Position { didSet { save("position", position.rawValue) } }
	@Published var layout: Layout { didSet { save("layout", layout.rawValue) } }
	@Published var screens: ScreenChoice { didSet { save("screens", screens.rawValue) } }
	@Published var size: BarSize { didSet { save("size", size.rawValue) } }
	@Published var shape: BarShape { didSet { save("shape", shape.rawValue) } }
	@Published var edge: Edge { didSet { save("edge", edge.rawValue) } }
	@Published var front: FrontStyle { didSet { save("front", front.rawValue) } }
	@Published var separators: Separators { didSet { save("separators", separators.rawValue) } }
	@Published var desktopStyle: DesktopStyle { didSet { save("desktops", desktopStyle.rawValue) } }
	@Published var runningDots: Bool { didSet { save("running", runningDots ? "on" : "off") } }
	/// A symbol before each item of the right-click menus.
	@Published var menuSymbols: Bool { didSet { save("menusymbols", menuSymbols ? "on" : "off") } }
	/// A group's button shows the edge of a second button behind it.
	@Published var groupStack: Bool { didSet { save("groupstack", groupStack ? "on" : "off") } }
	@Published var pointing: PointStyle { didSet { save("pointing", pointing.rawValue) } }
	@Published var motion: MotionLevel { didSet { save("motion", motion.rawValue) } }
	@Published var dragStyle: DragStyle { didSet { save("drag", dragStyle.rawValue) } }
	@Published var switcherMotion: SwitcherMotion { didSet { save("switcher", switcherMotion.rawValue) } }
	@Published var badgeMotion: BadgeMotion { didSet { save("badgemotion", badgeMotion.rawValue) } }
	@Published var openMotion: OpenMotion { didSet { save("opening", openMotion.rawValue) } }
	@Published var clickFeedback: ClickFeedback { didSet { save("click", clickFeedback.rawValue) } }
	/// Dragging a window's button onto a desktop number moves the window there.
	@Published var dropOnDesktop: Bool { didSet { save("droponDesktop", dropOnDesktop ? "on" : "off") } }
	/// "No windows on this desktop" in an empty bar.
	@Published var emptyText: Bool { didSet { save("emptytext", emptyText ? "on" : "off") } }
	/// Pointing at a group lists its windows (HoverList.swift).
	@Published var groupList: Bool { didSet { save("grouplist", groupList ? "on" : "off") } }
	/// Pointing at a window whose title is cut short shows it in full.
	@Published var fullTitle: Bool { didSet { save("fulltitle", fullTitle ? "on" : "off") } }
	@Published var listDelay: ListDelay { didSet { save("listdelay", listDelay.rawValue) } }
	@Published var minimiseInto: MinimiseInto { didSet { save("minimise", minimiseInto.rawValue) } }
	@Published var standIn: StandIn { didSet { save("standin", standIn.rawValue) } }
	@Published var ghostMotion: GhostMotion { didSet { save("movement", ghostMotion.rawValue) } }
	@Published var attention: Bool { didSet { save("attention", attention ? "on" : "off") } }
	@Published var sound: Bool { didSet { save("sound", sound ? "on" : "off") } }
	@Published var startAtLogin: Bool {
		didSet {
			save("login", startAtLogin ? "on" : "off")
			Self.applyLogin(startAtLogin)
		}
	}

	private init() {
		func get(_ n: String) -> String? { Settings.option(n) }
		grouping = Grouping(rawValue: get("grouping") ?? "") ?? .crowded
		glass = GlassKind(rawValue: get("glass") ?? "") ?? .frosted
		solidity = Double(get("solidity") ?? "") ?? 0
		position = Position(rawValue: get("position") ?? "") ?? .floating
		layout = Layout(rawValue: get("layout") ?? "") ?? .islands
		screens = ScreenChoice(rawValue: get("screens") ?? "") ?? .each
		size = BarSize(rawValue: get("size") ?? "") ?? .standard
		shape = BarShape(rawValue: get("shape") ?? "") ?? .capsule
		edge = Edge(rawValue: get("edge") ?? "") ?? .rim
		front = FrontStyle(rawValue: get("front") ?? "") ?? .raised
		separators = Separators(rawValue: get("separators") ?? "") ?? .fade
		desktopStyle = DesktopStyle(rawValue: get("desktops") ?? "") ?? .segmented
		runningDots = get("running") != "off"
		menuSymbols = get("menusymbols") != "off"
		groupStack = get("groupstack") == "on"
		pointing = PointStyle(rawValue: get("pointing") ?? "") ?? .tint
		// "on" and "off" are from before there were three levels.
		motion = MotionLevel(rawValue: get("motion") ?? "") ?? (get("motion") == "off" ? .off : .full)
		dragStyle = DragStyle(rawValue: get("drag") ?? "") ?? .lift
		switcherMotion = SwitcherMotion(rawValue: get("switcher") ?? "") ?? .slide
		badgeMotion = BadgeMotion(rawValue: get("badgemotion") ?? "") ?? .pop
		openMotion = OpenMotion(rawValue: get("opening") ?? "") ?? .grow
		clickFeedback = ClickFeedback(rawValue: get("click") ?? "") ?? .hop
		dropOnDesktop = get("droponDesktop") != "off"
		emptyText = get("emptytext") != "off"
		groupList = get("grouplist") != "off"
		fullTitle = get("fulltitle") != "off"
		listDelay = ListDelay(rawValue: get("listdelay") ?? "") ?? .short
		minimiseInto = MinimiseInto(rawValue: get("minimise") ?? "") ?? .dock
		standIn = StandIn(rawValue: get("standin") ?? "") ?? .outline
		ghostMotion = GhostMotion(rawValue: get("movement") ?? "") ?? .lamp
		attention = get("attention") != "off"
		sound = get("sound") != "off"
		// Start with the Mac, unless you turned that off.
		let login = get("login")
		startAtLogin = login != "off"
		if login == nil { Self.applyLogin(true) }
	}

	private func save(_ name: String, _ value: String) {
		if persist { Settings.setOption(name, value) }
	}

	/// Adds Leiste to (or removes it from) System Settings' Login Items.
	static func applyLogin(_ on: Bool) {
		let service = SMAppService.mainApp
		if on, service.status != .enabled { try? service.register() }
		if !on, service.status == .enabled { try? service.unregister() }
	}

	/// Sets an option by its name in options.txt (used by --snapshot's --opt).
	func set(_ name: String, _ value: String) {
		switch name {
		case "grouping": grouping = Grouping(rawValue: value) ?? grouping
		case "glass": glass = GlassKind(rawValue: value) ?? glass
		case "position": position = Position(rawValue: value) ?? position
		case "layout": layout = Layout(rawValue: value) ?? layout
		case "screens": screens = ScreenChoice(rawValue: value) ?? screens
		case "size": size = BarSize(rawValue: value) ?? size
		case "shape": shape = BarShape(rawValue: value) ?? shape
		case "edge": edge = Edge(rawValue: value) ?? edge
		case "front": front = FrontStyle(rawValue: value) ?? front
		case "separators": separators = Separators(rawValue: value) ?? separators
		case "desktops": desktopStyle = DesktopStyle(rawValue: value) ?? desktopStyle
		case "pointing": pointing = PointStyle(rawValue: value) ?? pointing
		case "running": runningDots = value == "on"
		case "groupstack": groupStack = value == "on"
		case "grouplist": groupList = value == "on"
		case "fulltitle": fullTitle = value == "on"
		case "listdelay": listDelay = ListDelay(rawValue: value) ?? listDelay
		default: break
		}
	}

	// MARK: Sizes that follow from the choices

	var height: CGFloat { size.height }
	/// Buttons leave 6 points of glass above and below them.
	var buttonHeight: CGFloat { height - 12 }
	var launcherIcon: CGFloat { (height * 0.65).rounded() }
	var windowIcon: CGFloat { (height * 0.43).rounded() }
	var fontSize: CGFloat { size == .compact ? 12.5 : (size == .large ? 14 : 13) }
	/// Islands only make sense floating; along the edge the bar is always one strip.
	var islands: Bool { layout == .islands && position == .floating }

	// The corners that go with the shape: a capsule for Liquid Glass, or the
	// rounded rectangle of the first version. Buttons stay concentric with the bar.
	// Along the edge the bar is a plain strip with square corners.
	var barCorner: CGFloat { position == .edge ? 0 : (shape == .capsule ? height / 2 : 16) }
	var buttonCorner: CGFloat { shape == .capsule ? buttonHeight / 2 : 10 }
	/// The gap between the bar and the screen's edges.
	var inset: CGFloat { position == .edge ? 0 : Metrics.inset }
	/// Movement, unless it's turned off here or Reduce Motion is on in System Settings.
	var moves: Bool { motion != .off && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
	/// The playful movements (lifting, tilting, hopping, popping): only at Full.
	/// At Reduced, things only fade.
	var playful: Bool { moves && motion == .full }
}
