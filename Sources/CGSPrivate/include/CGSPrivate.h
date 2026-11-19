// Undocumented macOS calls. Apple doesn't publish these, but they have been
// stable for many years and every window manager and bar for the Mac uses them.
// If a macOS update breaks Leiste, look here first.
#pragma once
#include <ApplicationServices/ApplicationServices.h>

typedef int CGSConnectionID;

// Our connection to the window server.
extern CGSConnectionID CGSMainConnectionID(void);

// Every screen with its desktops ("Spaces") and which one is showing.
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid);

// The window number behind an accessibility window, so the two lists can be matched.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindow);

// The desktop showing now, by its number inside the window server.
extern uint64_t CGSGetActiveSpace(CGSConnectionID cid);

// The desktops a window belongs to. Mask 7 asks for all kinds. Works for
// minimised windows too, which is how we know where they belong.
extern CFArrayRef CGSCopySpacesForWindows(CGSConnectionID cid, int mask, CFArrayRef windowIDs);

// Whether a window is put on screen ("ordered in") on some desktop, as opposed
// to hidden. A window on another desktop is ordered in, just not visible here;
// a closed-but-kept window (mail apps do this) is ordered out.
extern CGError CGSWindowIsOrderedIn(CGSConnectionID cid, CGWindowID wid, bool *isOrderedIn);
