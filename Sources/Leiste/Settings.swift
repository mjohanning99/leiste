// Leiste's settings are plain text files in
// ~/Library/Application Support/Leiste/, one app's bundle identifier per
// line, so you can read and change them by hand as well as from the bar.
//
//   launchers.txt   the pinned apps, left to right
//   badges.txt      the apps whose red badges are shown

import AppKit

enum Settings {
	static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		.appendingPathComponent("Leiste")

	static let launchersHeader = """
		# Leiste's launchers, one app's bundle identifier per line, left to right.
		# Find an app's identifier with: osascript -e 'id of app "Safari"'
		"""
	static let goToWindowHeader = """
		# Apps where a click on the bar takes you to their window instead of
		# opening a new one (their ⌘N does something else). One bundle identifier per line.
		# Right-click an app on the bar and pick "Clicking Opens" to change it.
		"""
	static let badgesHeader = """
		# The apps whose red badges Leiste shows, one bundle identifier per line.
		# Right-click an app on the bar and pick "Show Badges" to add or remove one.
		"""

	/// The launchers the first time: Finder, your default browser, Terminal and Mail.
	static func defaultLaunchers() -> [String] {
		var ids = ["com.apple.finder"]
		if let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.org")!),
		   let id = Bundle(url: browser)?.bundleIdentifier { ids.append(id) }
		return ids + ["com.apple.Terminal", "com.apple.mail"]
	}

	/// The badges shown the first time: Mail's and Messages'.
	static let defaultBadges = ["com.apple.mail", "com.apple.MobileSMS"]

	/// Reads a list, making the file with `defaults` the first time.
	static func read(_ name: String, header: String, defaults: () -> [String]) -> [String] {
		let file = folder.appendingPathComponent(name)
		if !FileManager.default.fileExists(atPath: file.path) { write(name, header: header, ids: defaults()) }
		let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
		return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty && !$0.hasPrefix("#") }
	}

	// options.txt has one "name = value" per line (for now only grouping).
	static let optionsHeader = """
		# Leiste's options, one "name = value" per line.
		# grouping = never, crowded or always (windows of one app share a button)
		"""

	static func option(_ name: String) -> String? {
		let text = (try? String(contentsOf: folder.appendingPathComponent("options.txt"), encoding: .utf8)) ?? ""
		for line in text.split(separator: "\n") where !line.hasPrefix("#") {
			let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
			if parts.count == 2, parts[0] == name { return parts[1] }
		}
		return nil
	}

	static func setOption(_ name: String, _ value: String) {
		let text = (try? String(contentsOf: folder.appendingPathComponent("options.txt"), encoding: .utf8)) ?? ""
		var lines = text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.hasPrefix(name + " ") && !$0.hasPrefix(name + "=") }
		lines.append("\(name) = \(value)")
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try? (optionsHeader + "\n" + lines.joined(separator: "\n") + "\n")
			.write(to: folder.appendingPathComponent("options.txt"), atomically: true, encoding: .utf8)
	}

	static func write(_ name: String, header: String, ids: [String]) {
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let text = header + "\n" + ids.joined(separator: "\n") + "\n"
		try? text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}
}
