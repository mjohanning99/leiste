// The bar's model: what it knows (windows, desktops, screens, pinned apps,
// badges) and when it looks again. It doesn't poll: apps announce their
// changes (Watch.swift), and the bar looks then, plus a slow safety look.
//
// The rest of BarModel is in files by purpose:
//   WindowReader.swift   reading the windows of this desktop
//   FullScreen.swift     stepping aside for full-screen apps and videos
//   FitAboveBar.swift    keeping windows above the bar
//   Clicks.swift         what clicks, groups, keys and dragging do
//   PinnedApps.swift     pinned apps and new windows
//   DesktopSwitch.swift  switching desktops
//   Signals.swift        badges, attention and sound
//   Tuck.swift           minimising into Leiste
//   MoveWindow.swift     moving a window to another desktop
//   Accessibility.swift  helpers for asking apps questions

import AppKit
import ApplicationServices
import CGSPrivate

struct BarWindow: Identifiable, Equatable {
	let id: CGWindowID
	let pid: pid_t
	var bundleID: String?
	var title: String
	var appName: String
	var icon: NSImage?
	var isActive: Bool
	var isMinimised: Bool
	static func == (a: BarWindow, b: BarWindow) -> Bool {
		a.id == b.id && a.title == b.title && a.isActive == b.isActive && a.isMinimised == b.isMinimised
	}
}

/// Several windows of one app, shown as one button when grouping is on.
struct WindowGroup: Identifiable {
	var id: String	// the app's bundle identifier, or its process number
	var windows: [BarWindow]
	var first: BarWindow { windows.first { $0.isActive } ?? windows[0] }
}

/// When windows of one app share a button.
enum Grouping: String, CaseIterable {
	case never, crowded, always
}

struct Launcher: Identifiable {
	let id: String	// the app's bundle identifier
	let url: URL
	// Looked up once, not every time the bar is drawn.
	let name: String
	let icon: NSImage

	init(id: String, url: URL) {
		self.id = id
		self.url = url
		name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
		icon = NSWorkspace.shared.icon(forFile: url.path)
	}
}

/// What the bar needs to know about an app, looked up once per app, not on every look.
struct AppInfo {
	let bundleID: String?
	let name: String
	let icon: NSImage?
}

@MainActor
final class BarModel: ObservableObject {
	@Published var windows: [BarWindow] = []
	@Published var desktops = DesktopInfo()
	@Published var launchers: [Launcher] = []
	@Published var trusted = AXIsProcessTrusted()
	// The badge of each app whose badges you want, by bundle identifier.
	@Published var badges: [String: String] = [:]
	// The apps whose badges you want (badges.txt).
	@Published var badgeApps: Set<String> = []
	// Apps asking for attention (their Dock icon bounced) until you look at them.
	@Published var attention: Set<String> = []
	// The bundle identifiers of everything playing sound now.
	@Published var playing: [String] = []
	// The pinned apps that are open, for the dots under them.
	@Published var running: Set<String> = []
	// Where the windows of each desktop are, for the "Pictures" switcher: by
	// desktop number, each window as a fraction of the screen (0 to 1).
	@Published var desktopPictures: [Int: [CGRect]] = [:]
	/// A full-screen app or video is in front on the main screen: its bar steps aside.
	@Published var fullScreen = false
	/// The screens whose bar steps aside for full screen (each screen can have its own).
	@Published var hiddenOn: Set<CGDirectDisplayID> = []
	/// The screens, the main one first, and each one's desktops.
	@Published var displays: [Display] = []
	@Published var desktopsOn: [CGDirectDisplayID: DesktopInfo] = [:]
	/// Which screen each window is on (minimised and tucked ones: where they were last).
	@Published var screenOf: [CGWindowID: CGDirectDisplayID] = [:]
	/// The screen is asleep or locked, or another user is using the Mac: Leiste rests.
	var resting = false
	// The window in front at the last look.
	var activeID: CGWindowID?
	var grouping: Grouping { Prefs.shared.grouping }

	// What the pointer is over, for the middle button and the scroll wheel.
	var pointedApp: String?
	var overDesktops = false
	var overDesktopsDisplay: CGDirectDisplayID?
	// The buttons as last shown, for the keyboard shortcuts.
	var shownGroups: [WindowGroup] = []
	// When each window was last in front, so a group starts with the latest one.
	var lastFront: [CGWindowID: Date] = [:]
	var bounceTimer: Timer?

	// The order of the buttons: first come, first placed, as in Plasma, and
	// changed only when you drag one.
	var order: [CGWindowID] = []
	// The accessibility side of each window, kept for raising it.
	var elements: [CGWindowID: AXUIElement] = [:]
	// Windows tucked into Leiste (Tuck.swift), and where each button is in the bar.
	var tucked: [CGWindowID: Tucked] = [:]
	// Windows flying into or out of the bar right now, and each window's last real place.
	var flying: Set<CGWindowID> = []
	var homes: [CGWindowID: CGRect] = [:]
	var buttonFrames: [CGWindowID: (display: CGDirectDisplayID, frame: CGRect)] = [:]
	/// Where each desktop number is in each screen's bar, and the number a
	/// window's button is being dragged over (it lights up). See Clicks.swift.
	var desktopFrames: [CGDirectDisplayID: [Int: CGRect]] = [:]
	@Published var dropTarget: (display: CGDirectDisplayID, desktop: Int)?
	// The window in front at the last look, to notice one coming forward.
	var previousActive: CGWindowID?
	// Minimised windows of every app, looked for once a second (it's slower).
	var minimised: [CGWindowID: (pid: pid_t, element: AXUIElement, title: String)] = [:]
	// The desktop each window was last seen on.
	var lastSpace: [CGWindowID: UInt64] = [:]
	var timer: Timer?
	var ticks = 0
	/// The model in use, for the announcements from macOS (Watch.swift).
	nonisolated(unsafe) static weak var current: BarModel?
	// Each app's name and icon, by process number.
	var apps: [pid_t: AppInfo] = [:]
	// A look is already on its way (announcements come in bursts).
	var lookDue: DispatchTime?
	// An app said a window was minimised or brought back: look for minimised windows soon.
	var minimisedChanged = true
	/// The windows on screen at the last look, for the yellow-button test (accessibility coordinates).
	static var onScreenFrames: [CGRect] = []
	// What each app's windows are called, remembered between looks: an app is
	// only asked again when it announced a change or shows a window we don't know.
	var known: [pid_t: [CGWindowID: (element: AXUIElement, title: String)]] = [:]
	// Palettes, helpers and windows an app didn't list (yet), with when we decided.
	// The verdict lasts 3 seconds: a brand-new window is often listed a moment late.
	var notWindows: [pid_t: [CGWindowID: Date]] = [:]
	var changedApps: Set<pid_t> = []
	// Where each window on screen is, from the window server (accessibility coordinates).
	var frames: [CGWindowID: CGRect] = [:]

	/// A model with made-up windows, for drawing the bar into a picture (--snapshot).
	init(sample grouping: Grouping) {
		// The sample uses apps every Mac has, not your own launchers.
		launchers = (["com.apple.finder", "com.apple.Safari", "com.apple.Terminal", "com.apple.mail", "com.apple.MobileSMS", "com.apple.Notes"])
			.compactMap { id in NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { Launcher(id: id, url: $0) } }
		badgeApps = Set(Settings.defaultBadges)
		trusted = true
		Prefs.shared.persist = false
		Prefs.shared.grouping = grouping
		desktops = DesktopInfo(count: 3, current: 2)
		func w(_ id: CGWindowID, _ bundle: String, _ title: String, active: Bool = false, min: Bool = false) -> BarWindow {
			let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
			let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? ""
			return BarWindow(id: id, pid: pid_t(bundle.count), bundleID: bundle, title: title, appName: name,
							 icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }, isActive: active, isMinimised: min)
		}
		windows = [w(1, "com.apple.Terminal", "~/Projects/leiste — zsh", active: true),
				   w(2, "com.apple.Safari", "Leiste on GitHub"),
				   w(3, "com.apple.Terminal", "~/Projects — zsh"),
				   w(4, "com.apple.MobileSMS", "Messages"),
				   w(5, "com.apple.Safari", "Swift documentation"),
				   w(6, "com.apple.Music", "Music"),
				   w(7, "com.apple.mail", "Inbox", min: true),
				   w(8, "com.apple.Safari", "Liquid Glass — Apple Developer")]
		badges = ["com.apple.MobileSMS": "3", "com.apple.mail": "12"]
		running = ["com.apple.finder", "com.apple.Safari", "com.apple.Terminal", "com.apple.mail", "com.apple.MobileSMS"]
		playing = ["com.apple.Music"]
		desktopPictures = [1: [CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.6), CGRect(x: 0.4, y: 0.3, width: 0.5, height: 0.6)],
						   2: [CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.85)], 3: []]
	}

	init() {
		launchers = Self.loadLaunchers()
		badgeApps = Set(Settings.read("badges.txt", header: Settings.badgesHeader) { Settings.defaultBadges })
		BarModel.current = self
		let centre = NSWorkspace.shared.notificationCenter
		centre.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
			let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			MainActor.assumeIsolated {
				// Looking at an app answers its call for attention.
				if let id = app?.bundleIdentifier { self?.attention.remove(id) }
				self?.lookSoon()
			}
		}
		centre.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
			let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			MainActor.assumeIsolated {
				if let app { Watch.add(app) }
				DockItems.reload()	// a new icon may be in the Dock
				self?.readRunning()
				self?.lookSoon()
			}
		}
		centre.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
			let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			MainActor.assumeIsolated {
				if let pid = app?.processIdentifier {
					Watch.remove(pid)
					self?.apps[pid] = nil
					self?.known[pid] = nil
					self?.notWindows[pid] = nil
					DockItems.reload()
				}
				self?.readRunning()
				self?.lookSoon()
			}
		}
		centre.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.desktopChanged() }
		}
		// Rest while nobody can see the bar: the screen asleep, another user's session, the screen locked.
		for (name, rest) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false),
							 (NSWorkspace.sessionDidResignActiveNotification, true), (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
			centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.rest(rest) }
			}
		}
		for (name, rest) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
			DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
				MainActor.assumeIsolated { self?.rest(rest) }
			}
		}
		Watch.addAll()
		readRunning()
		Sound.onChange = { [weak self] in self?.readSound() }
		Sound.listen()
		readSound()
		// A bounce is short, so the Dock is watched more often than the rest (only its icons' positions).
		// A bounce lasts at least a second, so every 0.6 seconds catches it.
		bounceTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.readBounce() }
		}
		bounceTimer?.tolerance = 0.1
		// The safety net and the slow things (sound, badges, minimised windows), once a second.
		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.slowLook() }
		}
		timer?.tolerance = 0.2
		slowLook()
	}

	/// Stops (or starts again) every look and listen while nobody can see the bar.
	func rest(_ on: Bool) {
		guard on != resting else { return }
		resting = on
		if !on {
			DockItems.reload()
			changedApps.formUnion(known.keys)
			minimisedChanged = true
			refresh()
		}
	}

	/// An app announced a change (Watch.swift).
	func heard(_ name: String, from pid: pid_t, about element: AXUIElement) {
		if resting { return }
		// A window's new title: only that title is read, and only its button
		// changes. (Some apps retitle many times a second, like a terminal's
		// spinner, so new titles are shown at most about three times a second.)
		if name == kAXTitleChangedNotification {
			// Things inside a window announce their titles too (a web page's text,
			// a tab); only the window's own title belongs on the button.
			let window: AXUIElement? = (Self.attribute(element, kAXRoleAttribute) as? String) == (kAXWindowRole as String)
				? element : Self.attribute(element, kAXWindowAttribute).map { $0 as! AXUIElement }
			if let window, let id = Self.windowID(window), known[pid]?[id] != nil {
				known[pid]?[id]?.title = Self.attribute(window, kAXTitleAttribute) as? String ?? ""
				retitleSoon()
			}
			return
		}
		if name == kAXWindowMiniaturizedNotification || name == kAXWindowDeminiaturizedNotification { minimisedChanged = true }
		// A window starting to go full screen says so at once, before macOS slides
		// over to its own desktop; stepping aside now means the bar never shows on the way.
		if !fullScreen, name == kAXWindowResizedNotification || name == kAXWindowMovedNotification || name == kAXFocusedWindowChangedNotification {
			let window: AXUIElement? = (Self.attribute(element, kAXRoleAttribute) as? String) == (kAXWindowRole as String)
				? element : Self.attribute(element, kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
			if let window, (Self.attribute(window, "AXFullScreen") as? Bool) == true {
				Log.write("a window says it is going full screen: bar steps aside early")
				fullWindow = window
				// The screen it is on, from where it is now.
				let pos: CGPoint? = Self.value(window, kAXPositionAttribute, .cgPoint, CGPoint.zero)
				let size: CGSize? = Self.value(window, kAXSizeAttribute, .cgSize, CGSize.zero)
				let disp = pos.flatMap { p in size.map { Display.containing(CGRect(origin: p, size: $0), in: displays) } } ?? displays.first
				fullWindowScreen = disp?.id
				showAgainAt = nil
				if let disp { hiddenOn.insert(disp.id) }
				if disp?.isMain ?? true { fullScreen = true }
			}
		}
		changedApps.insert(pid)
		lookSoon()
	}

	var retitlePending = false
	/// Puts the remembered titles on the buttons, without asking anyone anything.
	func retitleSoon() {
		guard !retitlePending else { return }
		retitlePending = true
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in
			guard let self else { return }
			self.retitlePending = false
			let updated = self.windows.map { w -> BarWindow in
				var w = w
				if let t = self.known[w.pid]?[w.id]?.title, !t.isEmpty { w.title = t }
				return w
			}
			if updated != self.windows { self.windows = updated }
		}
	}

	/// Looks again shortly, once for a whole burst of announcements.
	func lookSoon(after ms: Int = 50) {
		let when = DispatchTime.now() + .milliseconds(ms)
		// One look is already on its way and will come soon enough.
		if let pending = lookDue, pending <= when { return }
		lookDue = when
		DispatchQueue.main.asyncAfter(deadline: when) { [weak self] in
			guard let self, self.lookDue == when else { return }
			self.lookDue = nil
			self.refresh()
		}
	}

	/// Once a second: the safety-net look, plus the things nobody announces.
	func slowLook() {
		if Ghost.busy || resting { return }
		// Stored only when it changes: every store, even of the same value, redraws the bar.
		let nowTrusted = AXIsProcessTrusted()
		if nowTrusted != trusted {
			trusted = nowTrusted
			if nowTrusted {	// the permission was just granted: start everything that needs it
				Watch.addAll()
				YellowButton.install()
			}
		}
		ticks += 1
		// Sound is announced by Core Audio (readSound); this is only a safety net.
		if ticks % 30 == 0 { readSound() }
		if ticks % 2 == 1 { readBadges() }
		if ticks % 20 == 1 {
			minimisedChanged = true	// a full look for minimised windows now and then (apps announce the rest)
			// Only needed once windows have been tucked into Leiste.
			if Prefs.shared.minimiseInto == .leiste || !tucked.isEmpty { healParked() }
		}
		if Prefs.shared.desktopStyle == .pictures, ticks % 2 == 0 { readDesktopPictures() }
		if ticks % 30 == 0 { forgetClosedWindows() }
		// The safety net: apps announce their changes, so a look every 5 seconds
		// is plenty, and asking every app afresh every 15 seconds (for anything
		// one forgot to announce).
		if ticks % 15 == 0 { changedApps.formUnion(known.keys) }
		if ticks % 5 == 0 || minimisedChanged { refresh() }
	}

	/// Looks at the windows of this desktop, quickly. Called whenever an app
	/// announces a change, the desktop changes, and once a second.
	func refresh() {
		// While a stand-in flies into the bar, or nobody can see it, leave the apps in peace.
		if Ghost.busy || resting { return }
		// A switch is on its way and its buttons are already showing: don't look until it lands.
		if Date() < holdingUntil { return }
		let ds = Display.all()
		if ds != displays { displays = ds }
		let all = Desktops.readAll(ds)
		if all != desktopsOn { desktopsOn = all }
		let d = ds.first.flatMap { all[$0.id] } ?? Desktops.read()
		if d != desktops { desktops = d }
		if minimisedChanged {
			minimisedChanged = false
			readMinimised()
		}
		let w = readWindows()
		if w != windows { windows = w }
		// Remembered for this desktop, to show at once when it is switched to from
		// the bar. Only once settled: mid-slide, what is on screen can still be the
		// old desktop's windows, and remembering those would put them on the wrong desktop.
		if Date() > settlingUntil { byDesktop[CGSGetActiveSpace(CGSMainConnectionID())] = w }
		updateFullScreen(ds, all)
		fitAboveBar()
	}

	// When the bar may come back after full screen, if nothing changes before then.
	var showAgainAt: Date?
	// The window that said it was going full screen, and its screen.
	var fullWindow: AXUIElement?
	var fullWindowScreen: CGDirectDisplayID?
	// Apps with extra looks already on their way (lookAgainForNewWindows).
	var lookingAgain: Set<pid_t> = []
	// When each window was last shortened to fit above the bar.
	var shortenedAt: [CGWindowID: Date] = [:]
	// The buttons last seen on each desktop, by the window server's number for it.
	var byDesktop: [UInt64: [BarWindow]] = [:]
	// Until when a desktop switch is still sliding in.
	var settlingUntil = Date.distantPast
	// Until when the bar holds the desktop it switched to ahead of macOS.
	var holdingUntil = Date.distantPast

	/// The scroll wheel over the desktop numbers: one desktop per nudge.
	var wheel: CGFloat = 0
	var lastWheelMove = Date.distantPast

	/// The apps set to "Clicking opens: its window" (go-to-window.txt).
	@Published var goesToItsWindow: Set<String> = Set(Settings.read("go-to-window.txt", header: Settings.goToWindowHeader) { [] })

	/// The app's own "New Window" menu item: the one whose shortcut is ⌘N.

}
