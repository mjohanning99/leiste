#!/bin/sh
# Draws the bar in a series of settings into the folder given, for checking
# that a change to the code leaves the look exactly as it was:
#   tools/snapshots.sh /tmp/before; (change the code, build); tools/snapshots.sh /tmp/after
#   then compare the two folders (tools/compare.py).
out=${1:?give a folder}
mkdir -p "$out"
app=build/Leiste.app/Contents/MacOS/Leiste
n=0
while read -r name opts; do
	[ -z "$name" ] && continue
	# shellcheck disable=SC2086
	( $app --snapshot "$out/$name.png" $opts & p=$!; sleep 3; kill $p 2>/dev/null ) >/dev/null 2>&1
	n=$((n + 1))
done <<'LIST'
islands --opt position=floating --opt layout=islands --group crowded
islands-dark --dark --opt position=floating --opt layout=islands --group crowded
onebar --opt position=floating --opt layout=one --group never
edge --opt position=edge --group always
compact --opt size=compact --opt separators=dots --opt front=line --opt desktops=dots
large --opt size=large --opt separators=tray --opt front=accent --opt desktops=pictures --dark
outlines --opt separators=outlines --opt front=fill --opt desktops=numbers --opt shape=rounded
LIST
echo "$n pictures in $out"
