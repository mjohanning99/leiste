// The Settings window: how the bar looks and behaves, in tabs along the top
// like macOS's own apps (The Bar, Look, Motion, Windows, Pinned Apps,
// General). Opened from the bar's right-click menus ("Leiste Settings…").
// Every change shows at once: the controls are bound straight to Prefs
// (Prefs.swift), which saves each one to options.txt as it changes, and the
// bar redraws because it watches Prefs.

import AppKit
import SwiftUI

/// One tab's page: a grouped form of a fixed width, as tall as its content.
private struct Page<Content: View>: View {
	@ViewBuilder let content: Content
	var body: some View {
		Form { content }
			.formStyle(.grouped)
			.frame(width: 540)
			.fixedSize(horizontal: false, vertical: true)
	}
}

/// Where the bar is, its layout, which screens get one, its size and shape.
struct BarTab: View {
	@ObservedObject var prefs = Prefs.shared
	var body: some View {
		Page {
			Section {
				Picker("Position", selection: $prefs.position) {
					Text("Floating").tag(Position.floating)
					Text("Along the edge").tag(Position.edge)
				}
				.pickerStyle(.segmented)
				Picker("Layout", selection: $prefs.layout) {
					Text("Three islands").tag(Layout.islands)
					Text("One bar").tag(Layout.one)
				}
				.pickerStyle(.segmented)
				.disabled(prefs.position == .edge)
				.help("Along the edge the bar is always one strip.")
				Picker("Screens", selection: $prefs.screens) {
					Text("Each its own windows").tag(ScreenChoice.each)
					Text("Each every window").tag(ScreenChoice.all)
					Text("Main screen only").tag(ScreenChoice.main)
				}
				.help("With more than one screen: a bar on each, showing that screen’s windows or every window, or one bar on the screen with the menu bar.")
				Picker("Size", selection: $prefs.size) {
					Text("Compact").tag(BarSize.compact)
					Text("Standard").tag(BarSize.standard)
					Text("Large").tag(BarSize.large)
				}
				.pickerStyle(.segmented)
				Picker("Shape", selection: $prefs.shape) {
					Text("Capsule").tag(BarShape.capsule)
					Text("Rounded").tag(BarShape.rounded)
				}
				.pickerStyle(.segmented)
			}
		}
	}
}

/// The glass and how the buttons look.
struct LookTab: View {
	@ObservedObject var prefs = Prefs.shared
	var body: some View {
		Page {
			// The glass: clear or frosted, how see-through, the light along its edge.
			Section("Glass") {
				Picker("Glass", selection: $prefs.glass) {
					Text("Clear").tag(GlassKind.clear)
					Text("Frosted").tag(GlassKind.frosted)
				}
				.pickerStyle(.segmented)
				LabeledContent("See-through") {
					HStack {
						Slider(value: $prefs.solidity, in: 0...0.9)
						Text("Solid").foregroundStyle(.secondary)
					}
				}
				Picker("Edge", selection: $prefs.edge) {
					Text("Faint line").tag(Edge.line)
					Text("Bright rim").tag(Edge.rim)
					Text("Rim and glow").tag(Edge.glow)
				}
				.pickerStyle(.segmented)
			}
			// The window in front, separators, pointing, the desktop switcher, dots.
			Section("Buttons") {
				Picker("Window in front", selection: $prefs.front) {
					Text("Fill").tag(FrontStyle.fill)
					Text("Raised").tag(FrontStyle.raised)
					Text("Accent").tag(FrontStyle.accent)
					Text("Line").tag(FrontStyle.line)
				}
				.pickerStyle(.segmented)
				Picker("Between windows", selection: $prefs.separators) {
					Text("Fading lines").tag(Separators.fade)
					Text("Lines").tag(Separators.lines)
					Text("Dots").tag(Separators.dots)
					Text("A pill for each").tag(Separators.outlines)
					Text("A sunken tray").tag(Separators.tray)
					Text("Nothing").tag(Separators.none)
				}
				Picker("Pointing at a button", selection: $prefs.pointing) {
					Text("Tint").tag(PointStyle.tint)
					Text("Swell").tag(PointStyle.swell)
				}
				.pickerStyle(.segmented)
				Picker("Desktops", selection: $prefs.desktopStyle) {
					Text("Segmented").tag(DesktopStyle.segmented)
					Text("Numbers").tag(DesktopStyle.numbers)
					Text("Dots").tag(DesktopStyle.dots)
					Text("Pictures").tag(DesktopStyle.pictures)
				}
				.pickerStyle(.segmented)
				Toggle("Dots under pinned apps that are open", isOn: $prefs.runningDots)
				Toggle("Groups look like a stack", isOn: $prefs.groupStack)
				Toggle("Symbols in menus", isOn: $prefs.menuSymbols)
			}
		}
	}
}

/// How much moves, and each movement on its own.
struct MotionTab: View {
	@ObservedObject var prefs = Prefs.shared
	private var systemReduces: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
	var body: some View {
		Page {
			Section {
				Picker("Motion", selection: $prefs.motion) {
					Text("Full").tag(MotionLevel.full)
					Text("Reduced").tag(MotionLevel.reduced)
					Text("Off").tag(MotionLevel.off)
				}
				.pickerStyle(.segmented)
				Text(systemReduces
					 ? LocalizedStringKey("Reduce Motion is on in System Settings, so nothing moves whatever is chosen here.")
					 : LocalizedStringKey("Full: every movement below. Reduced: only gentle fades and slides; nothing lifts, hops or pops. Off: nothing moves."))
					.font(.callout).foregroundStyle(.secondary)
			}
			// Each movement's own choice; they apply at Full.
			Section("At Full") {
				Picker("Dragging a button", selection: $prefs.dragStyle) {
					Text("Lifts and tilts").tag(DragStyle.lift)
					Text("Lifts").tag(DragStyle.flat)
					Text("Stays flat").tag(DragStyle.none)
				}
				.pickerStyle(.segmented)
				Picker("Switching desktops", selection: $prefs.switcherMotion) {
					Text("Slides").tag(SwitcherMotion.slide)
					Text("Jumps").tag(SwitcherMotion.jump)
				}
				.pickerStyle(.segmented)
				Picker("A new badge", selection: $prefs.badgeMotion) {
					Text("Pops in").tag(BadgeMotion.pop)
					Text("Fades in").tag(BadgeMotion.fade)
				}
				.pickerStyle(.segmented)
				Picker("A window opening", selection: $prefs.openMotion) {
					Text("Grows into place").tag(OpenMotion.grow)
					Text("Fades in").tag(OpenMotion.fade)
				}
				.pickerStyle(.segmented)
				Picker("Clicking a pinned app", selection: $prefs.clickFeedback) {
					Text("Hops").tag(ClickFeedback.hop)
					Text("Presses in").tag(ClickFeedback.press)
					Text("Nothing").tag(ClickFeedback.none)
				}
				.pickerStyle(.segmented)
			}
			.disabled(prefs.motion != .full || systemReduces)
		}
	}
}

/// What happens to windows: grouping, minimising, dropping onto a desktop, signals.
struct WindowsTab: View {
	@ObservedObject var prefs = Prefs.shared
	var body: some View {
		Page {
			Section {
				Picker("Group windows by app", selection: $prefs.grouping) {
					Text("Never").tag(Grouping.never)
					Text("When the bar is full").tag(Grouping.crowded)
					Text("Always").tag(Grouping.always)
				}
				Toggle("Drag a window onto a desktop number to move it there", isOn: $prefs.dropOnDesktop)
				Toggle("Say so when a desktop has no windows", isOn: $prefs.emptyText)
				Toggle("Colour windows that ask for you", isOn: $prefs.attention)
				Toggle("Show which apps are playing sound", isOn: $prefs.sound)
			}
			Section("Minimising") {
				Picker("Minimise into", selection: $prefs.minimiseInto) {
					Text("The Dock").tag(MinimiseInto.dock)
					Text("Leiste").tag(MinimiseInto.leiste)
				}
				.pickerStyle(.segmented)
				.help("Into Leiste, a window shrinks into its button and waits out of sight. It isn't a real minimise, so Mission Control shows it as a tiny window in the corner.")
				if prefs.minimiseInto == .leiste {
					Picker("What flies in", selection: $prefs.standIn) {
						Text("Window outline").tag(StandIn.outline)
						Text("Glass pane").tag(StandIn.glass)
					}
					.pickerStyle(.segmented)
					Picker("Movement", selection: $prefs.ghostMotion) {
						Text("Magic lamp").tag(GhostMotion.lamp)
						Text("Squash").tag(GhostMotion.squash)
					}
					.pickerStyle(.segmented)
				}
			}
		}
	}
}

/// The pinned apps and the badges of apps that aren't pinned.
struct PinnedAppsTab: View {
	@ObservedObject var model: BarModel

	/// Lets you pick an app from the Applications folder (for "Add App…").
	private func chooseApp() -> String? {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.application]
		panel.directoryURL = URL(fileURLWithPath: "/Applications")
		panel.prompt = "Choose"
		guard panel.runModal() == .OK, let url = panel.url else { return nil }
		return BarModel.bundleID(of: url)
	}

	/// An app's icon and name, for the lists.
	private func appRow(_ id: String) -> some View {
		let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
		return HStack(spacing: 8) {
			if let url {
				Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
				Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
			} else {
				Text(id).foregroundStyle(.secondary)
			}
		}
	}

	/// Apps whose badges show but which aren't pinned (the second list).
	private var otherBadges: [String] {
		model.badgeApps.subtracting(model.launchers.map(\.id)).sorted()
	}

	var body: some View {
		Form {
			Section {
				ForEach(model.launchers) { l in
					HStack {
						appRow(l.id)
						Spacer()
						Toggle("Badges", isOn: Binding(get: { model.badgeApps.contains(l.id) }, set: { _ in model.toggleBadges(l.id) }))
							.toggleStyle(.checkbox)
						Button { model.togglePin(l.id) } label: { Image(systemName: "minus.circle") }
							.buttonStyle(.borderless)
							.help("Unpin \(l.name)")
					}
				}
				.onMove { model.moveLaunchers(from: $0, to: $1) }
				HStack {
					Text("Drag to change the order, here or on the bar.").foregroundStyle(.secondary).font(.callout)
					Spacer()
					Button("Add App\u{2026}") {
						if let id = chooseApp(), !model.isPinned(id) { model.togglePin(id) }
					}
				}
			} header: {
				Text("Pinned apps")
			}
			Section {
				ForEach(otherBadges, id: \.self) { id in
					HStack {
						appRow(id)
						Spacer()
						Button { model.toggleBadges(id) } label: { Image(systemName: "minus.circle") }
							.buttonStyle(.borderless)
							.help("Stop showing its badges")
					}
				}
				HStack {
					Text("Apps that aren\u{2019}t pinned, whose red badges show on their windows.").foregroundStyle(.secondary).font(.callout)
					Spacer()
					Button("Add App\u{2026}") {
						if let id = chooseApp(), !model.badgeApps.contains(id) { model.toggleBadges(id) }
					}
				}
			} header: {
				Text("Badges for other apps")
			}
		}
		.formStyle(.grouped)
		// As tall as its lists, up to a point; past that it scrolls.
		.frame(width: 540, height: min(600, CGFloat(model.launchers.count + otherBadges.count) * 34 + 200))
	}
}

/// Starting with the Mac, the welcome window, the settings files, About and Quit.
struct GeneralTab: View {
	@ObservedObject var prefs = Prefs.shared
	var body: some View {
		Page {
			Section {
				Toggle("Start Leiste with the Mac", isOn: $prefs.startAtLogin)
				LabeledContent("Setting up") {
					Button("Show the Welcome Window") { WelcomeWindow.show() }
				}
				LabeledContent("Settings files") {
					Button("Show the Files") { NSWorkspace.shared.open(Settings.folder) }
				}
				LabeledContent("Keyboard") {
					Text("Control-Option-1 to 9 brings that button\u{2019}s window forward.").foregroundStyle(.secondary)
				}
			}
			Section {
				LabeledContent("Start afresh") {
					Button("Reset to Defaults\u{2026}") { resetToDefaults() }
				}
			} footer: {
				Text("Puts every option in Settings back as it came; pinned apps and badges stay.")
					.font(.callout).foregroundStyle(.secondary)
			}
			Section {
				HStack(spacing: 12) {
					Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
					VStack(alignment: .leading, spacing: 2) {
						Text("Leiste \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
						Text("A task bar for the Mac, one desktop at a time.").foregroundStyle(.secondary)
						HStack(spacing: 12) {
							Link("github.com/mjohanning99/leiste", destination: URL(string: "https://github.com/mjohanning99/leiste")!)
							Link("Show Releases", destination: URL(string: "https://github.com/mjohanning99/leiste/releases")!)
						}
					}
					Spacer()
					Button("Quit Leiste") { NSApp.terminate(nil) }
				}
			}
		}
	}
}

/// Asks first, then removes options.txt (keeping "Start with the Mac") and
/// starts Leiste again, which reads every option afresh.
@MainActor
private func resetToDefaults() {
	let alert = NSAlert()
	alert.messageText = String(localized: "Reset every option to its default?")
	alert.informativeText = String(localized: "Pinned apps and badges stay as they are. Leiste starts again.")
	alert.addButton(withTitle: String(localized: "Reset"))
	alert.addButton(withTitle: String(localized: "Cancel"))
	guard alert.runModal() == .alertFirstButtonReturn else { return }
	let login = Settings.option("login")
	try? FileManager.default.removeItem(at: Settings.folder.appendingPathComponent("options.txt"))
	if let login { Settings.setOption("login", login) }
	// Start a new Leiste a moment after this one has quit.
	let again = Process()
	again.executableURL = URL(fileURLWithPath: "/bin/sh")
	again.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
	try? again.run()
	NSApp.terminate(nil)
}

/// The window itself: macOS's own tabs along the top (a tab view controller in
/// toolbar style, which also resizes the window to each page). Made once, then
/// shown again on the desktop you're on.
@MainActor
enum SettingsWindow {
	private static var window: NSWindow?

	private static func tab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
		let host = NSHostingController(rootView: view)
		host.sizingOptions = .preferredContentSize
		let item = NSTabViewItem(viewController: host)
		item.label = String(localized: String.LocalizationValue(title))
		host.title = item.label	// the window is named after the tab you're on
		item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.label)
		return item
	}

	static func show() {
		if window == nil {
			guard let model = BarModel.current else { return }
			window = make(model)
		}
		NSApp.activate()
		window?.makeKeyAndOrderFront(nil)
	}

	/// Draws each tab of the real window into `folder` as settings-<n>.png
	/// (--settings-snapshot, for the README). It is Leiste's own window, so no
	/// screen recording is needed; the window stays off screen.
	static func pictures(to folder: String, model: BarModel) {
		let w = make(model)
		w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
		NSApp.activate()
		w.makeKeyAndOrderFront(nil)
		guard let tabs = w.contentViewController as? NSTabViewController else { return }
		for i in tabs.tabViewItems.indices {
			tabs.selectedTabViewItemIndex = i
			RunLoop.main.run(until: Date().addingTimeInterval(0.6))
			guard let frame = w.contentView?.superview, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
			frame.cacheDisplay(in: frame.bounds, to: rep)
			try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(folder)/settings-\(i + 1).png"))
		}
	}

	private static func make(_ model: BarModel) -> NSWindow {
		do {
			let tabs = NSTabViewController()
			tabs.tabStyle = .toolbar
			tabs.addTabViewItem(tab("The Bar", "rectangle.bottomthird.inset.filled", BarTab()))
			tabs.addTabViewItem(tab("Look", "circle.lefthalf.filled", LookTab()))
			tabs.addTabViewItem(tab("Motion", "wind", MotionTab()))
			tabs.addTabViewItem(tab("Windows", "macwindow.on.rectangle", WindowsTab()))
			tabs.addTabViewItem(tab("Pinned Apps", "pin", PinnedAppsTab(model: model)))
			tabs.addTabViewItem(tab("General", "gearshape", GeneralTab()))
			let w = NSWindow(contentViewController: tabs)
			w.styleMask = [.titled, .closable]
			w.isReleasedWhenClosed = false
			w.collectionBehavior = [.moveToActiveSpace]	// open on the desktop you're on
			w.center()
			return w
		}
	}
}
