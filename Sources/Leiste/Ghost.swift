// The stand-in for a window being tucked into Leiste or brought back out.
// Leiste moves the real window in one go and animates only this stand-in, on
// the graphics card, so it stays smooth whatever the app does. It needs no
// permission: it never shows the window's contents, it draws its own.
//
// Two looks (Settings → Stand-in): a pane of glass, or a window outline (a
// title bar with the three dots, the body and the app's icon). Two movements
// (Settings → Movement): squash, where it shrinks into the button, or magic
// lamp, where it narrows and pours into the button bottom first, as in KDE
// Plasma. The magic lamp cuts the stand-in into thin strips and moves each one.

import AppKit
import QuartzCore

@MainActor
enum Ghost {
	/// Whether a stand-in is flying, so the bar can stop asking apps questions meanwhile.
	static var busy: Bool { !Run.running.isEmpty }

	/// Runs one animation. `window` is where the window is (or will be), `button`
	/// its button on the bar, both in accessibility coordinates (measured down
	/// from the top of the main screen). `done` runs at the end.
	static func fly(icon: NSImage?, window: CGRect, button: CGRect, shrinking: Bool, done: @escaping () -> Void) {
		guard let main = NSScreen.screens.first, Prefs.shared.moves, window.width > 10, window.height > 10 else { done(); return }
		// The overlay goes on the screen the window is on.
		let display = Display.containing(window, in: Display.all())
		let frame = display?.frame ?? main.frame
		let overlay = makeOverlay(frame)
		guard let root = overlay.contentView?.layer, let picture = draw(icon: icon, size: window.size) else { done(); return }
		let run = Run(overlay: overlay, root: root, picture: picture, window: window, button: button,
					  screenHeight: main.frame.height, shift: frame.origin, shrinking: shrinking, done: done)
		run.start()
	}

	/// A see-through window over the whole screen that ignores the mouse, just under the bar.
	private static func makeOverlay(_ frame: CGRect) -> NSWindow {
		let overlay = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
		overlay.isReleasedWhenClosed = false	// it is closed below; Swift lets it go after that
		overlay.isOpaque = false
		overlay.backgroundColor = .clear
		overlay.hasShadow = false
		overlay.ignoresMouseEvents = true
		overlay.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
		overlay.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
		let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
		root.wantsLayer = true
		overlay.contentView = root
		overlay.orderFrontRegardless()
		return overlay
	}

	/// Draws the stand-in at the window's size, in the bar's light or dark appearance.
	static func draw(icon: NSImage?, size: CGSize) -> CGImage? {
		// A little under full sharpness: it is only seen moving, and it is ready sooner.
		let scale = min(NSScreen.screens.first?.backingScaleFactor ?? 2, 1.5)
		let w = Int(size.width * scale), h = Int(size.height * scale)
		guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
								  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		ctx.scaleBy(x: scale, y: scale)
		let outline = Prefs.shared.standIn == .outline
		NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
			NSGraphicsContext.saveGraphicsState()
			NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
			let bounds = NSRect(origin: .zero, size: size)
			let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
			let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			if outline {
				// A plain window: its body, a title bar along the top and the three dots.
				NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
				body.fill()
				let bar = NSRect(x: 0, y: size.height - 30, width: size.width, height: 30)
				NSGraphicsContext.saveGraphicsState()
				body.addClip()
				(dark ? NSColor(white: 0.24, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
				bar.fill()
				NSGraphicsContext.restoreGraphicsState()
				for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
					c.setFill()
					NSBezierPath(ovalIn: NSRect(x: 14 + CGFloat(i) * 20, y: size.height - 21, width: 12, height: 12)).fill()
				}
				NSColor.separatorColor.setStroke()
			} else {
				// A pane of glass: a light, see-through fill with a bright edge.
				(dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 1, alpha: 0.5)).setFill()
				body.fill()
				NSColor(white: 1, alpha: dark ? 0.35 : 0.8).setStroke()
			}
			body.lineWidth = 1
			body.stroke()
			if let icon {
				let side = min(size.width, size.height) / 3
				icon.draw(in: NSRect(x: (size.width - side) / 2, y: (size.height - side) / 2 - (outline ? 8 : 0), width: side, height: side))
			}
			NSGraphicsContext.restoreGraphicsState()
		}
		return ctx.makeImage()
	}

	/// One animation in progress, driven by the screen's own refresh.
	@MainActor final class Run: NSObject {
		let overlay: NSWindow, picture: CGImage, window: CGRect, button: CGRect, screenHeight: CGFloat, shrinking: Bool
		/// Where the overlay starts on screen (AppKit coordinates), when it isn't on the main screen.
		let shift: CGPoint
		let done: () -> Void
		let strips: [CALayer]
		/// Holds the strips and fades them as one, so their overlaps never show.
		let group = CALayer()
		let duration: CFTimeInterval = 0.34
		static var running: Set<Run> = []

		init(overlay: NSWindow, root: CALayer, picture: CGImage, window: CGRect, button: CGRect,
			 screenHeight: CGFloat, shift: CGPoint = .zero, shrinking: Bool, done: @escaping () -> Void) {
			self.overlay = overlay; self.picture = picture; self.window = window; self.button = button
			self.screenHeight = screenHeight; self.shift = shift; self.shrinking = shrinking; self.done = done
			// Squash is the stand-in in one piece; the magic lamp cuts it into thin strips.
			// About one strip every 5 points of the window's height, 48 to 200 of them.
			let n = Prefs.shared.ghostMotion == .lamp ? max(48, min(200, Int(window.height / 5))) : 1
			strips = (0..<n).map { i in
				let layer = CALayer()
				layer.contents = picture
				layer.contentsGravity = .resize
				// Strip 0 is the top of the picture. Layers here count from the bottom up.
				layer.contentsRect = CGRect(x: 0, y: 1 - CGFloat(i + 1) / CGFloat(n), width: 1, height: 1 / CGFloat(n))
				// Smooth slanted sides; the top and bottom meet the next strip, so they stay sharp.
				layer.allowsEdgeAntialiasing = true
				layer.edgeAntialiasingMask = [.layerLeftEdge, .layerRightEdge]
				return layer
			}
			super.init()
			group.frame = root.bounds
			group.allowsGroupOpacity = true
			root.addSublayer(group)
			strips.forEach(group.addSublayer)
		}

		/// Works out the whole movement in advance (41 moments along the way) and
		/// hands it to macOS's animation engine, which plays it smoothly by itself,
		/// however busy Leiste's own thread is.
		func start() {
			Run.running.insert(self)
			let moments = 40
			let frames = (0...moments).map { layout(CGFloat($0) / CGFloat(moments)) }
			let times = (0...moments).map { NSNumber(value: Double($0) / Double(moments)) }
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			CATransaction.setCompletionBlock { [self] in
				MainActor.assumeIsolated {
					done()
					// A moment's overlap when growing, so the real window is back before the stand-in goes.
					let overlay = self.overlay
					DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(shrinking ? 0 : 60)) {
						// Closed, not just hidden: a hidden window would stay in memory for good.
						overlay.close()
						Run.running.remove(self)
					}
				}
			}
			func keyframes(_ key: String, _ values: [Any]) -> CAKeyframeAnimation {
				let a = CAKeyframeAnimation(keyPath: key)
				a.values = values
				a.keyTimes = times
				a.duration = duration
				a.calculationMode = .linear
				return a
			}
			for (i, layer) in strips.enumerated() {
				let last = frames[moments].strips[i]
				layer.bounds = last.bounds; layer.position = last.position; layer.setAffineTransform(last.transform)
				layer.add(keyframes("bounds", frames.map { NSValue(rect: $0.strips[i].bounds) }), forKey: "bounds")
				layer.add(keyframes("position", frames.map { NSValue(point: $0.strips[i].position) }), forKey: "position")
				layer.add(keyframes("transform", frames.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform($0.strips[i].transform)) }), forKey: "transform")
			}
			group.opacity = frames[moments].opacity
			group.add(keyframes("opacity", frames.map { NSNumber(value: $0.opacity) }), forKey: "opacity")
			CATransaction.commit()
		}

		/// Sets every strip for progress `p` at once (for the --ghost-test picture).
		func place(_ p: CGFloat) {
			let f = layout(p)
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			for (layer, s) in zip(strips, f.strips) {
				layer.bounds = s.bounds; layer.position = s.position; layer.setAffineTransform(s.transform)
			}
			group.opacity = f.opacity
			CATransaction.commit()
		}

		/// Where every strip is at progress `p` (0 to 1). Growing is shrinking played
		/// backwards. The edges between strips are what move, so neighbouring strips always meet.
		func layout(_ p: CGFloat) -> (strips: [(bounds: CGRect, position: CGPoint, transform: CGAffineTransform)], opacity: Float) {
			let q = shrinking ? p : 1 - p	// how far towards the button
			let n = strips.count
			// The bottom goes first, the top follows: that's what makes it pour.
			let lag: CGFloat = n > 1 ? 0.5 : 0
			// Each edge k (0 is the top of the window, n the bottom): its left, right and height.
			let edges: [(left: CGFloat, right: CGFloat, y: CGFloat, e: CGFloat)] = (0...n).map { k in
				let y = CGFloat(k) / CGFloat(n)
				let local = max(0, min(1, (q - (1 - y) * lag) / (1 - lag)))
				let e = local * local * (3 - 2 * local)	// smooth start and end
				func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
				return (mix(window.minX, button.minX), mix(window.maxX, button.maxX),
						mix(window.minY + window.height * y, button.minY + button.height * y), e)
			}
			var out: [(bounds: CGRect, position: CGPoint, transform: CGAffineTransform)] = []
			for i in 0..<n {
				let top = edges[i], bottom = edges[i + 1]
				// Each strip is slanted to follow the curve, so the sides stay smooth
				// lines rather than a staircase: its middle runs from the middle of the
				// edge below to the middle of the edge above.
				let width = max(((top.right - top.left) + (bottom.right - bottom.left)) / 2, 0.5)
				let height = max(bottom.y - top.y + 0.5, 0.5)	// half a point of overlap hides the seams
				let midTop = (top.left + top.right) / 2, midBottom = (bottom.left + bottom.right) / 2
				out.append((CGRect(x: 0, y: 0, width: width, height: height),
							// Accessibility measures from the top, the overlay from the bottom.
							CGPoint(x: (midTop + midBottom) / 2 - shift.x, y: screenHeight - (top.y + bottom.y) / 2 - shift.y),
							// Going up the strip (the overlay's y), its middle moves from midBottom to midTop.
							CGAffineTransform(a: 1, b: 0, c: (midTop - midBottom) / height, d: 1, tx: 0, ty: 0)))
			}
			// The whole stand-in fades evenly, so the strips never show as bands.
			return (out, Float(1 - 0.6 * q * q))
		}
	}
}
