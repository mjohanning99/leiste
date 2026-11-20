// Small helpers for asking apps questions through the Accessibility API, and
// for matching an accessibility window to the window server's number for it.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	func spacesForLog(_ id: CGWindowID) -> [UInt64] { spaces(of: id) }

	static func windowID(_ el: AXUIElement) -> CGWindowID? {
		var wid: CGWindowID = 0
		return _AXUIElementGetWindow(el, &wid) == .success ? wid : nil
	}

	static func attribute(_ el: AXUIElement, _ name: String) -> AnyObject? {
		var value: AnyObject?
		return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
	}

	/// Reads a position or size, which accessibility wraps in an AXValue.
	static func value<T>(_ el: AXUIElement, _ name: String, _ type: AXValueType, _ empty: T) -> T? {
		guard let v = attribute(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
		var out = empty
		return AXValueGetValue(v as! AXValue, type, &out) ? out : nil
	}

	static func axWindows(of app: AXUIElement) -> [AXUIElement] {
		answeredWindows(of: app) ?? []
	}

	/// An app's windows, or nil if it didn't answer (busy past the time limit).
	/// Not answering isn't having no windows: a busy app (Path Finder loading a
	/// folder) would otherwise lose its buttons until the next look.
	static func answeredWindows(of app: AXUIElement) -> [AXUIElement]? {
		var value: AnyObject?
		switch AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) {
		case .success: return value as? [AXUIElement] ?? []
		case .noValue, .attributeUnsupported: return []
		default: return nil
		}
	}

	private static var stallLogged: [pid_t: Date] = [:]

	/// Notes in the log that an app didn't answer, at most once a minute per app.
	func noteNoAnswer(_ pid: pid_t, _ what: String) {
		if let last = Self.stallLogged[pid], Date().timeIntervalSince(last) < 60 { return }
		Self.stallLogged[pid] = Date()
		Log.write("\(info(pid).bundleID ?? "pid \(pid)") didn't answer in time (\(what)): kept its buttons")
	}
}
