// swift-tools-version: 6.0
// Leiste: a bar along the bottom of the screen that shows the windows of the
// current desktop, like the task bar in KDE Plasma. Build it with tools/build.sh.
import PackageDescription

let package = Package(
	name: "Leiste",
	platforms: [.macOS(.v14)],
	targets: [
		// The few undocumented macOS calls we need, declared in C.
		.target(name: "CGSPrivate", path: "Sources/CGSPrivate"),
		.executableTarget(
			name: "Leiste",
			dependencies: ["CGSPrivate"],
			path: "Sources/Leiste"
		),
	],
	swiftLanguageModes: [.v5]
)
