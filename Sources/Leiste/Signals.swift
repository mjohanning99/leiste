// What the bar shows about apps besides their windows: red badges and calls
// for attention (both read from the Dock) and which apps are playing sound.

import AppKit
import ApplicationServices
import CGSPrivate

extension BarModel {
	/// Which apps are playing sound, for the speaker. Called when Core Audio says something changed.
	func readSound() {
		let p = Prefs.shared.sound ? Sound.playing() : []
		if p != playing { playing = p }
	}

	func readBounce() {
		if Ghost.busy || resting || fullScreen { return }
		guard trusted, Prefs.shared.attention else {
			if !attention.isEmpty { attention = [] }
			return
		}
		let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
		let new = Bounce.read().subtracting(attention).filter { $0 != front }
		if !new.isEmpty { attention.formUnion(new) }
	}

	/// Whether an app (or one of its helpers) is playing sound.
	func isPlaying(_ bundleID: String?) -> Bool {
		guard let id = bundleID else { return false }
		return playing.contains { $0 == id || $0.hasPrefix(id + ".") }
	}

	func readBadges() {
		let b = trusted ? Badges.read().filter { badgeApps.contains($0.key) } : [:]
		if b != badges { badges = b }
	}

	func toggleBadges(_ bundleID: String) {
		if badgeApps.contains(bundleID) { badgeApps.remove(bundleID) } else { badgeApps.insert(bundleID) }
		Settings.write("badges.txt", header: Settings.badgesHeader, ids: badgeApps.sorted())
		readBadges()
	}
}
