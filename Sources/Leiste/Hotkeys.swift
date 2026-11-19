// Control-Option-1 to 9: brings the first to ninth button's window forward,
// like Meta and a number in Plasma. Uses the system's hot keys, which need
// no permission and never get in the way of typing.

import Carbon
import Foundation

@MainActor
enum Hotkeys {
	/// Called with the button's number (1 to 9).
	static var onPress: ((Int) -> Void)?
	private static var refs: [EventHotKeyRef?] = []

	static func install() {
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
			var key = EventHotKeyID()
			GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
							  nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
			let n = Int(key.id)
			DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.onPress?(n) } }
			return noErr
		}, 1, &spec, nil, nil)

		// The key codes of 1 to 9 on the top row (they aren't in order).
		let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
		for (i, code) in digits.enumerated() {
			var ref: EventHotKeyRef?
			let id = EventHotKeyID(signature: OSType(0x4C53_5445), id: UInt32(i + 1))	// "LSTE"
			RegisterEventHotKey(code, UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
			refs.append(ref)
		}
	}
}
