// Listening instead of asking. For every app with windows, Leiste asks macOS
// to tell it when a window opens, closes, moves, changes size or title, is
// minimised or brought back, or another window comes to the front. Only then
// does the bar look again, so at rest Leiste does next to nothing. A slow look
// every second is kept as a safety net, for anything an app forgets to announce.

import AppKit
import ApplicationServices

@MainActor
enum Watch {
	private static var observers: [pid_t: AXObserver] = [:]

	/// What each app is asked to announce. Registered on the app itself, they
	/// cover all of its windows.
	private static let notifications = [
		kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
		kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
		kAXWindowMovedNotification, kAXWindowResizedNotification,
		kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
	]

	static func add(_ app: NSRunningApplication) {
		let pid = app.processIdentifier
		guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
		var observer: AXObserver?
		guard AXObserverCreate(pid, { _, element, name, _ in
			let name = name as String
			var pid: pid_t = 0
			AXUIElementGetPid(element, &pid)
			MainActor.assumeIsolated { BarModel.current?.heard(name, from: pid, about: element) }
		}, &observer) == .success, let observer else { return }
		let element = AXUIElementCreateApplication(pid)
		for n in notifications { AXObserverAddNotification(observer, element, n as CFString, nil) }
		CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
		observers[pid] = observer
	}

	/// The apps being listened to: the ones with windows (ordinary apps).
	static var pids: [pid_t] { Array(observers.keys) }

	static func remove(_ pid: pid_t) {
		guard let observer = observers.removeValue(forKey: pid) else { return }
		CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
	}

	/// Starts listening to every app that is open now (again, after the permission is granted).
	static func addAll() {
		NSWorkspace.shared.runningApplications.forEach(add)
	}
}
