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
		attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
	}
}
