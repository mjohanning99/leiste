// Leiste's log, ~/Library/Logs/Leiste.log: what it did when something might
// go wrong (new windows, odd desktop switches, full screen, shortened
// windows), never what is in your windows. It starts afresh past 1 MB.

import Foundation

/// A small log for finding problems: ~/Library/Logs/Leiste.log.
enum Log {
	static func write(_ line: String) {
		let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Leiste.log")
		// Starts afresh once it passes 1 MB, so it can never grow without limit.
		if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
			try? FileManager.default.removeItem(at: url)
		}
		let text = "\(Date().formatted(date: .omitted, time: .standard))  \(line)\n"
		if let h = try? FileHandle(forWritingTo: url) {
			h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
		} else {
			try? text.write(to: url, atomically: true, encoding: .utf8)
		}
	}
}
