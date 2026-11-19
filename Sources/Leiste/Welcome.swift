// The welcome window: the first time Leiste starts, a checklist of the four
// things that make it work as it should. Each step has a button that opens the
// right part of System Settings, and turns green by itself once it's done
// (Leiste looks once a second while the window is open). It can be opened
// again from Settings.

import AppKit
import SwiftUI

/// Whether each step is done, read from the system's own settings.
@MainActor
final class SetupState: ObservableObject {
	@Published var accessibility = false
	@Published var dockAside = false
	@Published var noJumping = false
	@Published var desktopShortcuts = false
	private var timer: Timer?

	func start() {
		read()
		timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.read() }
		}
	}

	func stop() {
		timer?.invalidate()
		timer = nil
	}

	private func read() {
		let dock = UserDefaults(suiteName: "com.apple.dock")
		set(\.accessibility, AXIsProcessTrusted())
		// Hidden and on the left or right.
		set(\.dockAside, dock?.bool(forKey: "autohide") == true && ["left", "right"].contains(dock?.string(forKey: "orientation") ?? "bottom"))
		// "When switching to an application, switch to a Space with its windows" is
		// on unless it was turned off (then the Dock stores it as false).
		set(\.noJumping, dock?.object(forKey: "workspaces-auto-swoosh") as? Bool == false)
		set(\.desktopShortcuts, Self.desktopShortcutsOn())
	}

	/// Stored only when it changes, so the window isn't redrawn every second.
	private func set(_ key: ReferenceWritableKeyPath<SetupState, Bool>, _ value: Bool) {
		if self[keyPath: key] != value { self[keyPath: key] = value }
	}

	/// "Switch to Desktop 1" (the system's hot key 118) is turned on.
	private static func desktopShortcutsOn() -> Bool {
		guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
			  let entry = all["118"] as? [String: Any] else { return false }
		return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1)
	}
}

struct WelcomeView: View {
	@ObservedObject var state: SetupState
	let done: () -> Void

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 8) {
				Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
				Text("Welcome to Leiste").font(.system(size: 24, weight: .bold))
				Text("Leiste shows the windows of the desktop you’re on. Four quick steps make it work as it should; each turns green once it’s done.")
					.font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
					.frame(maxWidth: 470)
					.fixedSize(horizontal: false, vertical: true)
			}
			VStack(spacing: 0) {
				StepRow(done: state.accessibility, title: "Allow Accessibility",
						text: "So Leiste can see your windows, bring them forward and read the Dock’s badges.",
						button: state.accessibility ? nil : "Open Accessibility",
						open: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
				Divider()
				StepRow(done: state.dockAside, title: "Hide the Dock and move it to the side",
						text: "Otherwise the Dock pops up over the bar whenever the pointer touches the bottom edge.",
						button: state.dockAside ? nil : "Open Desktop & Dock",
						open: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
				Divider()
				StepRow(done: state.noJumping, title: "Stop macOS jumping between desktops",
						text: "Turn off “When switching to an application, switch to a Space with open windows for the application”.",
						button: state.noJumping ? nil : "Open Desktop & Dock",
						open: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
				Divider()
				StepRow(done: state.desktopShortcuts, title: "Jump straight to a desktop", optional: true,
						text: "Turn on “Switch to Desktop 1, 2, …” under Keyboard Shortcuts, Mission Control, so the bar’s desktop buttons don’t slide through the others.",
						button: state.desktopShortcuts ? nil : "Open Keyboard",
						open: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
			}
			.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
			.padding(.top, 20)
			HStack {
				Text("You can open this again from Leiste Settings.").font(.system(size: 12)).foregroundStyle(.secondary)
				Spacer()
				Button("Start Using Leiste", action: done).keyboardShortcut(.defaultAction).controlSize(.large)
			}
			.padding(.top, 18)
		}
		.padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 26)
		.frame(width: 620)
		.fixedSize(horizontal: false, vertical: true)
	}
}

struct StepRow: View {
	let done: Bool
	let title: LocalizedStringKey
	var optional = false
	let text: LocalizedStringKey
	let button: LocalizedStringKey?
	let open: String

	var body: some View {
		HStack(spacing: 12) {
			ZStack {
				if done {
					Circle().fill(Color(nsColor: .systemGreen))
					Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
				} else {
					Circle().strokeBorder(.secondary, lineWidth: 1.5)
				}
			}
			.frame(width: 24, height: 24)
			.animation(.easeOut(duration: 0.25), value: done)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(title).fontWeight(.semibold)
					if optional {
						Text("OPTIONAL").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
							.padding(.horizontal, 4).padding(.vertical, 1)
							.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
					}
				}
				Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 8)
			if let button {
				Button(button) { if let url = URL(string: open) { NSWorkspace.shared.open(url) } }
			}
		}
		.padding(.horizontal, 16).padding(.vertical, 13)
		.accessibilityElement(children: .combine)
		.accessibilityValue(done ? Text("Done") : Text("Not done yet"))
	}
}

@MainActor
enum WelcomeWindow {
	private static var window: NSWindow?
	private static let state = SetupState()

	/// Shows it the first time Leiste starts (until "Start Using Leiste" is clicked).
	static func showIfFirstTime() {
		if Settings.option("welcomed") != "yes" { show() }
	}

	static func show() {
		if window == nil {
			let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
			w.titlebarAppearsTransparent = true
			w.titleVisibility = .hidden
			w.isReleasedWhenClosed = false
			w.collectionBehavior = [.moveToActiveSpace]
			w.contentView = NSHostingView(rootView: WelcomeView(state: state) { finish() })
			w.center()
			window = w
			NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
				MainActor.assumeIsolated { state.stop() }
			}
		}
		state.start()
		NSApp.activate()
		window?.makeKeyAndOrderFront(nil)
	}

	private static func finish() {
		Settings.setOption("welcomed", "yes")
		window?.close()
	}
}
