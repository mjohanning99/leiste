// The red badges (unread counts) that apps put on their Dock icons. Apps
// hand them to the Dock, and the Dock shows them to accessibility tools even
// while it is hidden, so we read them from there. Each app item in the Dock
// has its address (AXURL) and its badge (AXStatusLabel).

import AppKit
import ApplicationServices

/// The Dock's app icons, remembered between looks: going through the whole
/// Dock each time would cost far more than reading a few values off each icon.
@MainActor
enum DockItems {
	private static var cache: [(element: AXUIElement, bundleID: String)] = []
	private static var fetched = Date.distantPast

	/// The Dock's app icons, looked up again every 20 seconds or when one has gone.
	static func all() -> [(element: AXUIElement, bundleID: String)] {
		if cache.isEmpty || Date().timeIntervalSince(fetched) > 20 { reload() }
		return cache
	}

	/// Forgets the icons, so the next look finds them afresh (an app opened or quit).
	static func reload() {
		fetched = Date()
		cache = []
		guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
		let app = AXUIElementCreateApplication(dock.processIdentifier)
		AXUIElementSetMessagingTimeout(app, 0.25)
		// The Dock's window has one list, and the list has the icons.
		for list in BarModel.attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
			for item in BarModel.attribute(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
				guard (BarModel.attribute(item, kAXSubroleAttribute) as? String) == "AXApplicationDockItem",
					  let url = BarModel.attribute(item, kAXURLAttribute) as? URL,
					  let id = Bundle(url: url)?.bundleIdentifier else { continue }
				cache.append((item, id))
			}
		}
	}
}

@MainActor
enum Badges {
	/// Every badge the Dock shows now, by the app's bundle identifier.
	static func read() -> [String: String] {
		var result: [String: String] = [:]
		for item in DockItems.all() {
			if let label = BarModel.attribute(item.element, "AXStatusLabel") as? String, !label.isEmpty { result[item.bundleID] = label }
		}
		return result
	}
}

/// Apps asking for attention. The Dock bounces their icon, and accessibility
/// shows each icon's position, so a bouncing icon is the one standing out of
/// line with the others (whether the Dock is hidden or not).
@MainActor
enum Bounce {
	static func read() -> Set<String> {
		// Which way the icons would bounce: up from a bottom Dock, sideways from a side one.
		let side = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
		var across: [(String, CGFloat)] = []
		var lost = false
		for item in DockItems.all() {
			guard let pos: CGPoint = BarModel.value(item.element, kAXPositionAttribute, .cgPoint, CGPoint.zero) else { lost = true; continue }
			across.append((item.bundleID, side == "bottom" ? pos.y : pos.x))
		}
		if lost { DockItems.reload() }	// an icon went away; find them afresh next time
		guard across.count >= 3 else { return [] }
		let middle = across.map(\.1).sorted()[across.count / 2]
		return Set(across.filter { abs($0.1 - middle) > 4 }.map(\.0))
	}
}
