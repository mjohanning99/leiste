// Leiste starts here: it makes a bar along the bottom of each screen (or of
// the main screen only), puts the view in it and asks for the Accessibility
// permission.

import AppKit
import CGSPrivate
import Combine
import SwiftUI

/// A panel that never takes the keyboard from the window you're working in,
/// shows on every desktop and stays at the Dock's level.
final class BarPanel: NSPanel {
	init() {
		super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		isOpaque = false
		backgroundColor = .clear
		hasShadow = false	// the glass draws its own edge
		level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
		collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
		isMovable = false
		hidesOnDeactivate = false
	}
	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}

/// Lets the first click on the bar press a button straight away.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	/// One bar per screen that has one, by the screen's number.
	private var panels: [CGDirectDisplayID: BarPanel] = [:]
	var model: BarModel!
	private var watch: AnyCancellable?
	private var fullWatch: AnyCancellable?
	private var screensWatch: AnyCancellable?

	func applicationDidFinishLaunching(_ note: Notification) {
		// Never wait more than half a second for an app to answer (macOS would wait
		// up to six), so a slow app can't hold up the bar.
		AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
		// Shows the system's request for the Accessibility permission the first time.
		let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
		_ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)

		model = BarModel()
		model.restoreTuckedFromLastTime()
		_ = Prefs.shared	// reads the options and, the first time, adds Leiste to Login Items

		// The middle button and the scroll wheel, which SwiftUI has no words for.
		NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .scrollWheel]) { [weak self] event in
			MainActor.assumeIsolated {
				guard let model = self?.model else { return }
				if event.type == .otherMouseDown, event.buttonNumber == 2 { model.middleClick() }
				if event.type == .scrollWheel {
					let d = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
					model.scroll(d, precise: event.hasPreciseScrollingDeltas)
				}
			}
			return event
		}
		Hotkeys.onPress = { [weak self] n in self?.model.pressShortcut(n) }
		Hotkeys.install()
		// With "Minimise into Leiste" on, a window's own yellow button tucks it into Leiste too.
		YellowButton.onClick = { [weak self] id in
			guard let model = self?.model, let w = model.windows.first(where: { $0.id == id }) else { return }
			model.tuck(w)
		}
		YellowButton.install()
		// The first time: the checklist of what makes Leiste work as it should.
		WelcomeWindow.showIfFirstTime()
		place()
		// A full-screen app or video in front: that screen's bar fades away, and back afterwards.
		fullWatch = model.$hiddenOn.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] hidden in
			MainActor.assumeIsolated { self?.stepAside(hidden) }
		}
		// The bars move as soon as their position or size is changed in Settings,
		// and are made again when the choice of screens changes.
		watch = Prefs.shared.$position.combineLatest(Prefs.shared.$size).dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
			MainActor.assumeIsolated { self?.place() }
		}
		screensWatch = Prefs.shared.$screens.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
			MainActor.assumeIsolated { self?.place() }
		}

		NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.place() }
		}
	}

	/// Fades away the bars of screens showing something full screen, and back the others.
	func stepAside(_ hidden: Set<CGDirectDisplayID>) {
		for (id, panel) in panels {
			let hide = hidden.contains(id)
			guard (panel.alphaValue == 0) != hide else { continue }
			Log.write("bar \(hide ? "hides" : "shows")")
			NSAnimationContext.runAnimationGroup({ context in
				context.duration = Prefs.shared.moves ? 0.25 : 0
				panel.animator().alphaValue = hide ? 0 : 1
			}, completionHandler: {
				MainActor.assumeIsolated {
					// Hidden, it stays out of the way of clicks too.
					panel.ignoresMouseEvents = hide
				}
			})
		}
	}

	/// Windows tucked into Leiste go back where they were when it quits.
	func applicationWillTerminate(_ note: Notification) {
		model?.untuckAll()
	}

	/// A bar along the bottom of each screen that gets one (Settings → Screens):
	/// 8 points in from each edge when floating, right on the edge otherwise.
	/// Screens that came or went get their bars made or taken away.
	func place() {
		let all = Display.all()
		let wanted = Prefs.shared.screens == .main ? Array(all.prefix(1)) : all
		for (id, panel) in panels where !wanted.contains(where: { $0.id == id }) {
			panel.orderOut(nil)
			panel.close()
			panels[id] = nil
		}
		var frames: [CGDirectDisplayID: CGRect] = [:]
		let i = Prefs.shared.inset
		for d in wanted {
			let panel = panels[d.id] ?? {
				let p = BarPanel()
				p.contentView = FirstClickHostingView(rootView: BarView(model: model, display: d))
				panels[d.id] = p
				return p
			}()
			// The screen's place may have changed (a new arrangement), so the view is told again.
			(panel.contentView as? FirstClickHostingView<BarView>)?.rootView = BarView(model: model, display: d)
			let f = d.frame
			panel.setFrame(NSRect(x: f.minX + i, y: f.minY + i, width: f.width - 2 * i, height: Prefs.shared.height), display: true)
			panel.orderFrontRegardless()
			frames[d.id] = panel.frame
		}
		BarModel.panelFrames = frames
		model.refresh()
	}
}

MainActor.assumeIsolated {
	let args = CommandLine.arguments
	if let i = args.firstIndex(of: "--ax-probe"), i + 1 < args.count { _ = NSApplication.shared; axProbe(args[i + 1]) }
	if let i = args.firstIndex(of: "--welcome-snapshot"), i + 1 < args.count {
		_ = NSApplication.shared
		welcomeSnapshot(to: args[i + 1], dark: args.contains("--dark"))
	}
	if let i = args.firstIndex(of: "--settings-snapshot"), i + 1 < args.count {
		_ = NSApplication.shared
		NSApp.setActivationPolicy(.accessory)
		Prefs.shared.persist = false
		SettingsWindow.pictures(to: args[i + 1], model: BarModel(sample: .crowded))
		exit(0)
	}
	if let i = args.firstIndex(of: "--ghost-test"), i + 1 < args.count { _ = NSApplication.shared; Prefs.shared.persist = false; Prefs.shared.ghostMotion = .lamp; ghostTest(to: args[i + 1]) }
	if let i = args.firstIndex(of: "--dump-dock"), i + 1 < args.count { dumpDock(to: args[i + 1]) }
	if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
		_ = NSApplication.shared
		let g = args.firstIndex(of: "--group").flatMap { args.indices.contains($0 + 1) ? Grouping(rawValue: args[$0 + 1]) : nil } ?? .never
		snapshot(to: args[i + 1], dark: args.contains("--dark"), grouping: g)
	}
	let app = NSApplication.shared
	let delegate = AppDelegate()
	app.delegate = delegate
	app.setActivationPolicy(.accessory)
	app.run()
}
