// The desktops (Apple calls them Spaces): how many there are, which one is
// showing and how to switch. macOS has no public way to do any of this, so
// reading uses CGSPrivate and switching presses the same keys you would.

import AppKit
import CGSPrivate

struct DesktopInfo: Equatable {
	var count: Int = 1
	var current: Int = 1	// counted from 1, like the keyboard shortcuts
	var spaceIDs: [UInt64] = []	// the window server's number for each desktop, in order
	/// False while a full-screen app's own space is showing (macOS's full screen, the green button).
	var onDesktop = true
}

enum Desktops {
	/// Reads the desktops of every screen, by the screen's number. With
	/// "Displays have separate Spaces" off, all screens share one set.
	static func readAll(_ displays: [Display]) -> [CGDirectDisplayID: DesktopInfo] {
		guard let list = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else { return [:] }
		var result: [CGDirectDisplayID: DesktopInfo] = [:]
		for d in displays {
			let entry = list.first { ($0["Display Identifier"] as? String) == d.uuid }
				?? list.first { ($0["Display Identifier"] as? String) == "Main" }
				?? list.first
			if let entry { result[d.id] = info(from: entry) }
		}
		return result
	}

	/// The desktops listed in one screen's entry of the Spaces settings.
	private static func info(from display: [String: Any]) -> DesktopInfo {
		let spaces = (display["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }
		let currentID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
		let index = spaces.firstIndex { ($0["ManagedSpaceID"] as? Int) == currentID }
		let ids = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
		return DesktopInfo(count: max(spaces.count, 1), current: (index ?? 0) + 1, spaceIDs: ids, onDesktop: index != nil)
	}

	/// Reads the desktops of the main screen (the one with the menu bar).
	static func read() -> DesktopInfo {
		guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]],
			  !displays.isEmpty else { return DesktopInfo() }

		// With "Displays have separate Spaces" off there is one entry called "Main".
		// Otherwise each screen has its own, named by the screen's UUID.
		let mainUUID: String? = {
			guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else { return nil }
			return CFUUIDCreateString(nil, uuid) as String?
		}()
		let display = displays.first { ($0["Display Identifier"] as? String) == "Main" }
			?? displays.first { ($0["Display Identifier"] as? String) == mainUUID }
			?? displays[0]

		// Type 0 is an ordinary desktop; full-screen apps get spaces of their own, which we skip.
		let spaces = (display["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }
		let currentID = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
		let index = spaces.firstIndex { ($0["ManagedSpaceID"] as? Int) == currentID }
		let ids = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
		return DesktopInfo(count: max(spaces.count, 1), current: (index ?? 0) + 1, spaceIDs: ids, onDesktop: index != nil)
	}

	/// Goes to desktop `number` (from 1). Uses Control-number when those
	/// shortcuts are turned on, otherwise Control-arrow as many times as needed.
	static func go(to number: Int, from info: DesktopInfo) {
		guard number != info.current else { return }
		Log.write("go to desktop \(number) from \(info.current)")
		// "Switch to Desktop n" (hot keys 118 to 126) jumps straight there, if it's turned on.
		if number <= 9, let key = shortcut(117 + number) {
			Keys.press(key.code, flags: key.flags)
			return
		}
		// Otherwise "Move left/right a space" (hot keys 79 and 81), once per desktop.
		guard let key = shortcut(number > info.current ? 81 : 79) else {
			Log.write("  no desktop shortcut is turned on")
			return
		}
		for i in 0..<abs(number - info.current) {
			DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(i * 60)) {
				Keys.press(key.code, flags: key.flags)
			}
		}
	}

	/// One of the system's hot keys, exactly as System Settings stores it, if
	/// it's turned on. It must be pressed with all its stored flags: the arrow
	/// shortcuts carry the hidden "fn" and "number pad" flags of arrow keys,
	/// and without them macOS doesn't take the press for the shortcut.
	static func shortcut(_ id: Int) -> (code: CGKeyCode, flags: CGEventFlags)? {
		guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
			  let entry = all[String(id)] as? [String: Any],
			  (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1),
			  let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3 else {
			// Not stored at all means macOS's own default: on for the arrows, off for the numbers.
			if id == 79 { return (123, [.maskControl, .maskSecondaryFn, .maskNumericPad]) }
			if id == 81 { return (124, [.maskControl, .maskSecondaryFn, .maskNumericPad]) }
			return nil
		}
		return (CGKeyCode(params[1]), CGEventFlags(rawValue: UInt64(params[2])))
	}
}

/// Pressing keys as if on the keyboard. Needs the Accessibility permission.
enum Keys {
	static func press(_ key: CGKeyCode, flags: CGEventFlags, to pid: pid_t? = nil) {
		let source = CGEventSource(stateID: .hidSystemState)
		for down in [true, false] {
			guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
			event.flags = flags
			if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
		}
	}
}
