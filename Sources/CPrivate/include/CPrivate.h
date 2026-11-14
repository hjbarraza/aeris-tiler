// Private macOS calls used by Aeris Tiler. None of them needs SIP off.
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

// Accessibility window element -> window server id.
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *wid);

// SkyLight (the window server client library).
int SLSMainConnectionID(void);
CFArrayRef SLSCopyManagedDisplaySpaces(int cid) CF_RETURNS_RETAINED;
CFArrayRef SLSCopySpacesForWindows(int cid, int selector, CFArrayRef windows) CF_RETURNS_RETAINED;
CGError SLSOrderWindow(int cid, uint32_t wid, int mode, uint32_t relative_to);
CGError SLSSpaceSetCompatID(int cid, uint64_t sid, int workspace);
CGError SLSSetWindowListWorkspace(int cid, uint32_t *windows, int count, int workspace);
void SLSMoveWindowsToManagedSpace(int cid, CFArrayRef windows, uint64_t sid);

/// Focus a window. With `raise` false the window takes the keyboard but keeps its place in the
/// stack (focus follows mouse). `prev_*` is the window that has focus now.
void aeris_focus_window(pid_t pid, uint32_t wid, pid_t prev_pid, uint32_t prev_wid, bool raise);

/// Send a window to another space. Returns false when the window server refuses.
bool aeris_move_window_to_space(uint32_t wid, uint64_t sid);
