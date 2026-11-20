# Changelog

What changed in each version of Leiste, newest first.

## 1.1.0 (20 November 2026)

- **Fixed:** a window snapped under the bar twice in a row (with a window tiler) stayed there until you clicked something. It now moves above the bar within a second.
- **Fixed:** a window that a window tiler centres over the whole screen ended partly under the bar. It's now moved up to end just above it (windows you drag there yourself stay put).
- **Smoother with window tilers that animate:** Leiste waits until a window has stopped gliding before fitting it above the bar, instead of tugging at it mid-way.
- **Fixed:** after switching back to a desktop where every window was minimised into Leiste, one of them could grow back out by itself.
- **Fixed:** the order you dragged the buttons into was forgotten after switching desktops.
- **Fixed:** an app busy for a moment (Path Finder loading a folder, say) could lose its buttons until the next look. They now stay while it's busy.
- A group's button no longer shows a second outline behind it; the grey count says it's a group (the stack look is a choice under Look).

## 1.0.0 (19 November 2026)

The first public version. Everything below it was tested privately before it went public.

- **Move to Desktop.** Right-click a window's button to send it to another desktop. Leiste carries it across the way a drag would. You go along with it.
- **Small movements.** A button you drag lifts out of the bar and leans into the move while the others make room. The desktop switcher's highlight slides, new badges pop in, a new window's button grows into place and a pinned app hops when clicked. Settings → Motion has Full, Reduced (only gentle fades and slides) and Off, plus a choice for each movement. macOS's Reduce Motion always stops them.
- **Drop a window onto a desktop.** Drag a window's button onto a desktop number: the number lights up. Let go and the window moves there.
- **Symbols in the right-click menus**, as in macOS 26's own menus, so they are quicker to scan (Settings → Look can turn them off).
- **Settings in tabs:** The Bar, Look, Motion, Windows, Pinned Apps and General, each a short page. General has **Reset to Defaults** and a link to the releases.
- **Friendlier notices.** Without the Accessibility permission, the bar says so plainly and has an **Open Settings** button. An empty desktop says "No windows on this desktop" (can be turned off).
- **Fixed:** the button of the window in front could stick out past the end of its glass.
- **Fixed:** opening Mission Control could leave windows resized. In rare cases the bar could also freeze.

## 0.11.0 (19 November 2026, private)

- **A welcome window.** The first time Leiste starts, a checklist walks you through the setup: each step opens the right part of System Settings and turns green once it's done. It can be opened again from Settings.
- **A bar on every screen.** With more than one screen, each gets a bar with its own windows (or every window, or only the main screen gets one: Settings → Screens). Each screen's desktops, full screen and magic lamp are its own.
- **German.** Leiste speaks German on Macs set to German.
- **Pinned apps without a new window.** Clicking a pinned app whose windows are on another desktop still opens a new window here (⌘N). If none appears within a second (some chat apps have only one window), you're taken to the window it has instead of nothing happening. For apps whose ⌘N does something else, such as writing a new message in a mail app, right-click them and choose **Clicking Opens: Its Window**.
- **Apps with their window closed.** Clicking a pinned app that is running without a window (a mail app after its window was closed) opens its window on the desktop you're on, as the Dock does, instead of doing nothing or taking you elsewhere.
- **One app for every Mac.** Leiste now runs on Intel Macs as well as Apple silicon, from macOS 14 on.
- **VoiceOver.** Every button says what it is: the window and its app, whether it's in front, minimised, asking for attention or playing sound, plus its badge.
- **Fixed:** after switching desktops with the keyboard or trackpad, the bar sometimes stayed empty until you clicked something.

## 0.10.0 (19 November 2026, private)

- **Minimise into Leiste.** A choice in Settings: the window pours into its own button on the bar like a magic lamp (or simply shrinks) and grows back out of it. A window's own yellow button does the same.
- **Full screen.** The bar fades away while a full-screen app or video is in front. It comes back afterwards.
- **Pinned apps and badges in Settings.** Add, remove and reorder pinned apps. Choose whose badges to show.
- **Faster desktop switches from the bar.** Clicking a desktop or scrolling over the switcher changes the buttons at once.
- **Much lighter.** Leiste listens for window changes instead of asking apps over and over. At rest it uses well under 1 % of the processor and about 25 MB of memory. It rests while the screen is asleep or locked.
- **Fixed:** new windows that didn't appear until clicked, text from inside a window showing as its title, windows on the wrong desktop's bar and a small memory leak.

## 0.9.0 (19 November 2026, private)

The first release: a bar of the current desktop's windows with pinned apps, badges, grouping, a desktop switcher, Liquid Glass and its Settings.
