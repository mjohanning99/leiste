#!/bin/sh
# Builds Leiste.app into build/. Run it from anywhere: tools/build.sh
# Needs only Apple's Command Line Tools (xcode-select --install); Xcode works too.
set -e
cd "$(dirname "$0")/.."

# Keep the compiler's caches inside the project, so the build touches nothing else.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
# One app for both kinds of Mac: Apple silicon (arm64) and Intel (x86_64), from macOS 14 on.
set -- -c release --arch arm64 --arch x86_64 --disable-sandbox --manifest-cache local \
	--cache-path .build/swiftpm-cache --config-path .build/swiftpm-config --security-path .build/swiftpm-security
swift build "$@"
bin=$(swift build "$@" --show-bin-path)

app=build/Leiste.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Leiste" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
cp Resources/Leiste.icns "$app/Contents/Resources/"
# Its languages: English (the texts in the code) and German.
cp -R Resources/en.lproj Resources/de.lproj "$app/Contents/Resources/"

# Signing. Leiste needs the Accessibility permission, and macOS ties that
# permission to the app's signature. An ad hoc signature (the default) changes
# with every build, so after rebuilding you have to remove Leiste from the
# Accessibility list and add it again. To avoid that, make a code-signing
# certificate of your own in Keychain Access and put its name in a file called
# .signing-identity next to this project's README; builds then stay "the same app".
identity=-
# (LEISTE_ADHOC=1 ignores the file, for builds you hand to other people.)
if [ -f .signing-identity ] && [ -z "$LEISTE_ADHOC" ]; then identity=$(cat .signing-identity); fi
codesign --force --sign "$identity" "$app"
echo "Built $app"
