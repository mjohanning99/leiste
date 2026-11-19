#!/bin/sh
# Builds Leiste and zips it for a GitHub release: dist/Leiste-<version>.zip
set -e
cd "$(dirname "$0")/.."
# Signed ad hoc: a personal certificate would only confuse other people's Macs.
LEISTE_ADHOC=1 tools/build.sh
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
mkdir -p dist
rm -f "dist/Leiste-$version.zip"
ditto -c -k --keepParent build/Leiste.app "dist/Leiste-$version.zip"
shasum -a 256 "dist/Leiste-$version.zip"
# Build your own copy again, signed as usual, so its permission stays put.
tools/build.sh >/dev/null
