// Tools for checking Leiste without a screen recording, started with an
// option instead of as the bar (see AGENTS.md): pictures of the bar, the
// welcome window and the magic lamp, the Dock's items and how an app answers.
// They look only; none of them changes anything.

import AppKit
import ApplicationServices
import CGSPrivate
import SwiftUI

/// `Leiste --snapshot out.png [--dark] [--group never|crowded|always]` draws the bar with made-up windows
/// into a picture and quits, so the layout can be checked without a screen
/// recording. The glass doesn't show in a picture, so a plain grey stands in.
@MainActor func snapshot(to path: String, dark: Bool, grouping: Grouping) {
	Glass.plain = true
	let model = BarModel(sample: grouping)
	// --opt name=value, as many as you like, tries other looks without touching your settings.
	let args = CommandLine.arguments
	for (i, a) in args.enumerated() where a == "--opt" && i + 1 < args.count {
		let parts = args[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
		if parts.count == 2 { Prefs.shared.set(parts[0], parts[1]) }
	}
	let view = BarView(model: model)
		.frame(width: 1100, height: Prefs.shared.height)
		.padding(14)
		.background(dark ? Color(white: 0.18) : Color(white: 0.86))
		.environment(\.colorScheme, dark ? .dark : .light)
	let renderer = ImageRenderer(content: view)
	renderer.scale = 2
	guard let image = renderer.cgImage,
		  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
	try? png.write(to: URL(fileURLWithPath: path))
	exit(0)
}

/// `--list-snapshot out.png [--dark]`: draws a group's list (HoverList.swift)
/// with sample windows, and a single window's full title under it.
@MainActor func listSnapshot(to path: String, dark: Bool) {
	Glass.plain = true
	let model = BarModel(sample: .always)
	model.windows[1].isMinimised = true
	model.windows[4].isActive = true
	let view = VStack(spacing: 0) {
		GroupList(model: model, ids: [5, 2, 8, 3])
		FullTitle(title: "Liquid Glass — Apple Developer Documentation and a few more words", app: "Safari")
	}
	.padding(10)
	.background(dark ? Color(white: 0.18) : Color(white: 0.86))
	.environment(\.colorScheme, dark ? .dark : .light)
	let renderer = ImageRenderer(content: view)
	renderer.scale = 2
	guard let image = renderer.cgImage,
		  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
	try? png.write(to: URL(fileURLWithPath: path))
	exit(0)
}

/// `--dump-dock out.txt`: writes every attribute of every Dock item, to find
/// what the Dock tells accessibility tools. A tool for us, not for every day.
@MainActor func dumpDock(to path: String) {
	var text = "trusted: \(AXIsProcessTrusted())\n"
	if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
		let app = AXUIElementCreateApplication(dock.processIdentifier)
		for list in (BarModel.attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
			for item in (BarModel.attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
				var names: CFArray?
				AXUIElementCopyAttributeNames(item, &names)
				text += "---\n"
				for n in (names as? [String] ?? []) {
					text += "\(n) = \(BarModel.attribute(item, n).map { String(describing: $0).prefix(120) } ?? "nil")\n"
				}
			}
		}
	}
	try? text.write(toFile: path, atomically: true, encoding: .utf8)
	exit(0)
}

/// `--ghost-test out.png`: draws the magic lamp half way, to check the strips.
@MainActor func ghostTest(to path: String) {
	let size = CGSize(width: 600, height: 420)
	let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app")
	guard let picture = Ghost.draw(icon: icon, size: size),
		  let ctx = CGContext(data: nil, width: 900, height: 700, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
							  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
	ctx.setFillColor(CGColor(gray: 0.55, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 700))
	let root = CALayer(); root.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
	let window = CGRect(x: 60, y: 40, width: size.width, height: size.height)
	let button = CGRect(x: 600, y: 640, width: 200, height: 34)
	let run = Ghost.Run(overlay: NSWindow(), root: root, picture: picture, window: window, button: button,
						screenHeight: 700, shrinking: true, done: {})
	for (i, p) in [0.0, 0.5].enumerated() {
		run.place(CGFloat(p))
		ctx.saveGState(); ctx.translateBy(x: CGFloat(i) * 0, y: 0)
		root.render(in: ctx)
		ctx.restoreGState()
	}
	let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
	try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
	exit(0)
}

/// `--welcome-snapshot out.png [--dark]`: draws the welcome window into a picture.
@MainActor func welcomeSnapshot(to path: String, dark: Bool) {
	let state = SetupState()
	state.accessibility = true	// as on a Mac where the first step is done
	let view = WelcomeView(state: state) {}
		.background(Color(nsColor: .windowBackgroundColor))
		.environment(\.colorScheme, dark ? .dark : .light)
	let renderer = ImageRenderer(content: view)
	renderer.scale = 2
	guard let image = renderer.cgImage,
		  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
	try? png.write(to: URL(fileURLWithPath: path))
	exit(0)
}

/// `--ax-probe id`: how long an app takes to list its windows, and what the window
/// server knows about them, written to the log. Looks only. Start with `open -n … --args`.
@MainActor func axProbe(_ id: String) {
	guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { Log.write("probe \(id): not running"); exit(0) }
	let pid = app.processIdentifier
	let ax = AXUIElementCreateApplication(pid)
	AXUIElementSetMessagingTimeout(ax, 10)
	for _ in 0..<3 {
		let t = Date()
		var value: AnyObject?
		let r = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value)
		let wins = value as? [AXUIElement] ?? []
		Log.write(String(format: "probe %@: windows in %.0f ms, result %d, %d windows", id, Date().timeIntervalSince(t) * 1000, r.rawValue, wins.count))
		for w in wins {
			Log.write("probe   \(BarModel.windowID(w) ?? 0) role \(BarModel.attribute(w, kAXSubroleAttribute) as? String ?? "-") minimised \(BarModel.attribute(w, kAXMinimizedAttribute) as? Bool ?? false)")
		}
	}
	let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
	for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid {
		let b = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
		let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
		var orderedIn = false
		CGSWindowIsOrderedIn(CGSMainConnectionID(), wid, &orderedIn)
		Log.write("probe   server: \(wid) layer \(info[kCGWindowLayer as String] ?? 0) on screen \(info[kCGWindowIsOnscreen as String] as? Bool ?? false) ordered in \(orderedIn) desktops \(BarModel.spacesOf(wid)) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))")
	}
	exit(0)
}
