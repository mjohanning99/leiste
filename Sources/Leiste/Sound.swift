// Which apps are playing sound. Since macOS 14.2 Core Audio lists every
// process that uses audio and whether it is sending sound out right now. No
// permission is needed. Leiste doesn't ask over and over: Core Audio tells it
// when the list of processes changes or one starts or stops playing.

import CoreAudio
import Foundation

@MainActor
enum Sound {
	/// Called when something starts or stops playing.
	static var onChange: (() -> Void)?
	private static var watched: Set<AudioObjectID> = []
	private static var listening = false

	private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
		AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
	}

	/// Starts listening: to the list of processes, and to each one starting or stopping.
	static func listen() {
		guard !listening else { return }
		listening = true
		var list = address(kAudioHardwarePropertyProcessObjectList)
		AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, DispatchQueue.main) { _, _ in
			MainActor.assumeIsolated {
				watchEach()
				onChange?()
			}
		}
		watchEach()
	}

	private static func processes() -> [AudioObjectID] {
		var a = address(kAudioHardwarePropertyProcessObjectList)
		var size: UInt32 = 0
		let system = AudioObjectID(kAudioObjectSystemObject)
		guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
		var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
		guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
		return ids
	}

	/// Listens to every process we aren't listening to yet.
	private static func watchEach() {
		let now = Set(processes())
		watched = watched.intersection(now)	// gone processes take their listeners with them
		for p in now.subtracting(watched) {
			var a = address(kAudioProcessPropertyIsRunningOutput)
			AudioObjectAddPropertyListenerBlock(p, &a, DispatchQueue.main) { _, _ in
				MainActor.assumeIsolated { onChange?() }
			}
			watched.insert(p)
		}
	}

	/// The bundle identifiers of everything playing sound now. Browsers and
	/// chat apps often play through a helper ("com.example.app.helper"), so
	/// a window's app counts as playing when an identifier starts with its own.
	static func playing() -> [String] {
		var result: [String] = []
		for p in processes() {
			var running: UInt32 = 0
			var runningSize = UInt32(MemoryLayout<UInt32>.size)
			var a = address(kAudioProcessPropertyIsRunningOutput)
			guard AudioObjectGetPropertyData(p, &a, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
			var bundle: Unmanaged<CFString>?
			var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
			a.mSelector = kAudioProcessPropertyBundleID
			if AudioObjectGetPropertyData(p, &a, 0, nil, &bundleSize, &bundle) == noErr, let b = bundle?.takeRetainedValue() {
				result.append(b as String)
			}
		}
		// Sorted, so the same apps always make the same list (a different order would redraw the bar).
		return Array(Set(result)).sorted()
	}
}
