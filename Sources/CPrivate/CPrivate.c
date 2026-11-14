// Window focus through the window server.
// The event records follow yabai (MIT, github.com/asmvik/yabai).
#include "CPrivate.h"
#include <string.h>
#include <unistd.h>

extern CGError _SLPSSetFrontProcessWithOptions(ProcessSerialNumber *psn, uint32_t wid, uint32_t mode);
extern CGError SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *bytes);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static bool psn_for_pid(pid_t pid, ProcessSerialNumber *psn) { return GetProcessForPID(pid, psn) == noErr; }
#pragma clang diagnostic pop

// Tell an app that one of its windows became the key window.
static void make_key(ProcessSerialNumber *psn, uint32_t wid) {
    uint8_t down[0xf8] = {0}, up[0xf8] = {0};
    down[0x04] = 0xf8; down[0x08] = 0x01; down[0x3a] = 0x10;
    up[0x04] = 0xf8;   up[0x08] = 0x02;   up[0x3a] = 0x10;
    memcpy(down + 0x3c, &wid, sizeof(wid)); memset(down + 0x20, 0xff, 0x10);
    memcpy(up + 0x3c, &wid, sizeof(wid));   memset(up + 0x20, 0xff, 0x10);
    SLPSPostEventRecordTo(psn, down);
    SLPSPostEventRecordTo(psn, up);
}

void aeris_focus_window(pid_t pid, uint32_t wid, pid_t prev_pid, uint32_t prev_wid, bool raise) {
    ProcessSerialNumber psn;
    if (!psn_for_pid(pid, &psn)) return;
    // Two windows of one app: the app only switches key window without raising when the old
    // window is told it lost focus first.
    if (!raise && pid == prev_pid && prev_wid && prev_wid != wid) {
        uint8_t lose[0xf8] = {0}, gain[0xf8] = {0};
        lose[0x04] = 0xf8; lose[0x08] = 0x0d; lose[0x8a] = 0x02;
        gain[0x04] = 0xf8; gain[0x08] = 0x0d; gain[0x8a] = 0x01;
        memcpy(lose + 0x3c, &prev_wid, sizeof(prev_wid));
        memcpy(gain + 0x3c, &wid, sizeof(wid));
        SLPSPostEventRecordTo(&psn, lose);
        usleep(10000);
        SLPSPostEventRecordTo(&psn, gain);
    }
    _SLPSSetFrontProcessWithOptions(&psn, wid, 0x200 /* user generated */);
    make_key(&psn, wid);
}
