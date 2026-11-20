// The screens. Leiste can show a bar on each (Settings → The bar → Screens),
// and it needs to know which screen each window is on. Accessibility and the
// window server measure from the top-left corner of the main screen (the one
// with the menu bar), downwards; AppKit measures from its bottom-left, upwards.

import AppKit

struct Display: Equatable, Identifiable {
	let id: CGDirectDisplayID
	/// The screen's rectangle in accessibility coordinates.
	let axFrame: CGRect
	/// The screen's rectangle in AppKit coordinates (for placing windows on it).
	let frame: CGRect
	let isMain: Bool
	/// Where the usable part starts, below the menu bar (accessibility coordinates).
	let axTop: CGFloat
	/// How the Spaces settings name this screen.
	let uuid: String

	/// Every screen, the main one first.
	@MainActor static func all() -> [Display] {
		let screens = NSScreen.screens
		guard let main = screens.first else { return [] }
		let h = main.frame.height
		return screens.enumerated().compactMap { i, s in
			guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
			let f = s.frame
			let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? ""
			return Display(id: id, axFrame: CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height),
						   frame: f, isMain: i == 0, axTop: h - s.visibleFrame.maxY, uuid: uuid)
		}
	}

	/// The screen a rectangle (accessibility coordinates) is mostly on: the one holding its middle.
	static func containing(_ r: CGRect, in displays: [Display]) -> Display? {
		let middle = CGPoint(x: r.midX, y: r.midY)
		return displays.first { $0.axFrame.contains(middle) } ?? displays.first
	}
}
