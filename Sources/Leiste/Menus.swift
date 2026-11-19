// The right-click menus: of the bar itself, of a window or a group of windows
// and the part about the app (pinning, badges, what a click opens). Each item
// has a symbol before it, as in macOS 26's own menus, so a menu is quick to
// scan (Settings → Look → "Symbols in menus" turns them off).

import AppKit
import SwiftUI

/// A menu item's text with its symbol, or the text alone when symbols are off.
struct ItemLabel: View {
	let title: LocalizedStringKey
	let symbol: String
	init(_ title: LocalizedStringKey, _ symbol: String) { self.title = title; self.symbol = symbol }
	var body: some View {
		if Prefs.shared.menuSymbols { Label(title, systemImage: symbol) } else { Text(title) }
	}
}

/// The menu for the bar itself (right-click where there is no button).
struct BarMenu: View {
	var body: some View {
		Button { SettingsWindow.show() } label: { ItemLabel("Leiste Settings\u{2026}", "gearshape") }
		Button { NSApp.terminate(nil) } label: { ItemLabel("Quit Leiste", "power") }
	}
}

/// The part of every right-click menu that is about the app: pinning and badges.
struct AppMenu: View {
	@ObservedObject var model: BarModel
	let bundleID: String
	let name: String

	var body: some View {
		Button { model.togglePin(bundleID) } label: {
			if model.isPinned(bundleID) { ItemLabel("Unpin \(name)", "pin.slash") } else { ItemLabel("Pin \(name) to the Bar", "pin") }
		}
		Toggle(isOn: Binding(get: { model.badgeApps.contains(bundleID) }, set: { _ in model.toggleBadges(bundleID) })) {
			ItemLabel("Show \(name)\u{2019}s Badges", "app.badge")
		}
		// What a click on its pinned app (or a middle click) does when it has windows
		// on another desktop: ⌘N for a new one, or go to the window it has.
		Picker(selection: Binding(get: { model.goesToItsWindow.contains(bundleID) },
								  set: { model.setGoesToItsWindow(bundleID, $0) })) {
			Text("A New Window").tag(false)
			Text("Its Window").tag(true)
		} label: {
			ItemLabel("Clicking Opens", "cursorarrow.click")
		}
	}
}

/// The menu for a window's (or a group's) button.
struct WindowMenu: View {
	@ObservedObject var model: BarModel
	let group: WindowGroup

	var body: some View {
		let w = group.first
		if group.windows.count > 1 {
			// A group lists its windows first, the one in front ticked.
			ForEach(group.windows) { gw in
				Toggle(gw.title, isOn: Binding(get: { gw.isActive }, set: { _ in model.raise(gw) }))
			}
			Divider()
		}
		if let id = w.bundleID {
			Button { model.newWindow(id) } label: { ItemLabel("New \(w.appName) Window", "macwindow.badge.plus") }
		}
		if group.windows.count == 1 {
			if w.isMinimised {
				Button { model.raise(w) } label: { ItemLabel("Restore", "macwindow") }
			} else {
				Button { model.minimise(w) } label: { ItemLabel("Minimise", "minus.square") }
			}
			Button { model.close(w) } label: { ItemLabel("Close Window", "xmark.square") }
			if model.desktops.count > 1, !w.isMinimised {
				// Carries the window to another desktop (MoveWindow.swift); you go along with it.
				Menu {
					ForEach(1...model.desktops.count, id: \.self) { n in
						// A numbered square for each desktop (the symbols go up to 50).
						Button { model.move(w, toDesktop: n) } label: { ItemLabel("Desktop \(n)", n <= 50 ? "\(n).square" : "square") }
							.disabled(n == model.desktops.current)
					}
				} label: {
					ItemLabel("Move to Desktop", "rectangle.portrait.and.arrow.right")
				}
			}
		} else {
			Button { group.windows.filter { !$0.isMinimised }.forEach(model.minimise) } label: { ItemLabel("Minimise All", "minus.square") }
			Button { group.windows.forEach(model.close) } label: { ItemLabel("Close All \(group.windows.count) Windows", "xmark.square") }
		}
		Divider()
		if let id = w.bundleID { AppMenu(model: model, bundleID: id, name: w.appName) }
		if let id = w.bundleID {
			Button { model.quit(id) } label: { ItemLabel("Quit \(w.appName)", "power") }
		}
		Divider()
		BarMenu()
	}
}
