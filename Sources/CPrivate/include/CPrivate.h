// Private macOS calls used by Aeris Tiler. None of them needs SIP off.
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

// Accessibility window element -> window server id.
AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *wid);

// SkyLight (the window server client library).
int SLSMainConnectionID(void);
CFArrayRef SLSCopyManagedDisplaySpaces(int cid) CF_RETURNS_RETAINED;
CGError SLSOrderWindow(int cid, uint32_t wid, int mode, uint32_t relative_to);

/// Focus a window. With `raise` false the window takes the keyboard but keeps its place in the
/// stack (focus follows mouse). `prev_*` is the window that has focus now.
void aeris_focus_window(pid_t pid, uint32_t wid, pid_t prev_pid, uint32_t prev_wid, bool raise);
