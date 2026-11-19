/*
 * mac_lid_lock - lock the screen when the lid closes, without sleep.
 *
 * With `pmset -a disablesleep 1` a lid close only turns off the built-in
 * panel. macOS locks on system sleep or display sleep, so it does not lock.
 * This program listens for kIOPMMessageClamshellStateChange from
 * IOPMrootDomain. On an open-to-closed change it runs
 * `pmset displaysleepnow`, which locks when the password is required
 * immediately after display sleep. A 5 s poll of AppleClamshellState is a
 * backup in case a message is missed.
 *
 * While the file $HOME/Library/Application Support/mac-lid-lock/paused
 * exists (mac_lid_lock.sh pause), a lid close does not lock. Use it when
 * you work with the lid closed on an external display.
 *
 * Usage: mac_lid_lock [LOG]. LOG is the file launchd sends stdout to. At
 * start and on every lid change, lines older than 180 days are cut from
 * the start of LOG.
 *
 * Run it as a user LaunchAgent (mac_lid_lock.sh install), so it is in the
 * GUI session. Build: clang -Os -framework IOKit -framework CoreFoundation
 *   -o mac_lid_lock mac_lid_lock.c
 */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreAudio/CoreAudio.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

extern char **environ;

enum { LID_UNKNOWN = -1, LID_OPEN = 0, LID_CLOSED = 1 };

static const double kPollSeconds = 5.0;
static const double kIdleSeconds = 300.0;
static int g_idle_locked;
static const time_t kKeepSeconds = 180 * 24 * 60 * 60;
/* A larger log is left alone instead of read into memory. */
static const off_t kMaxPruneBytes = 64 * 1024 * 1024;

static const char kPausedFile[] =
    "/Library/Application Support/mac-lid-lock/paused";

static io_service_t g_root;
static int g_lid = LID_UNKNOWN;
static const char *g_log_path;

static void logf_line(const char *msg, const char *source)
{
    char ts[32];
    time_t now = time(NULL);
    struct tm tm;

    localtime_r(&now, &tm);
    strftime(ts, sizeof ts, "%Y-%m-%d %H:%M:%S", &tm);
    printf("%s mac_lid_lock: %s source=%s\n", ts, msg, source);
    fflush(stdout);
}

/* Is p the start of "YYYY-MM-DD HH:MM:SS"? n is the bytes left. */
static int has_timestamp(const char *p, size_t n)
{
    static const char shape[] = "dddd-dd-dd dd:dd:dd";
    size_t i;

    if (n < sizeof shape - 1) {
        return 0;
    }
    for (i = 0; i < sizeof shape - 1; i++) {
        if (shape[i] == 'd' ? (p[i] < '0' || p[i] > '9') : p[i] != shape[i]) {
            return 0;
        }
    }
    return 1;
}

static int read_all(int fd, char *buf, size_t size)
{
    size_t done = 0;
    ssize_t n;

    while (done < size) {
        n = pread(fd, buf + done, size - done, (off_t)done);
        if (n <= 0) {
            return -1;
        }
        done += (size_t)n;
    }
    return 0;
}

static int write_all(int fd, const char *buf, size_t size)
{
    size_t done = 0;
    ssize_t n;

    while (done < size) {
        n = pwrite(fd, buf + done, size - done, (off_t)done);
        if (n <= 0) {
            return -1;
        }
        done += (size_t)n;
    }
    return 0;
}

/*
 * Cuts the lines before the first line stamped within kKeepSeconds.
 * Lines are in time order, so the old ones are all at the start. Lines
 * without a stamp before that point go too.
 */
static void prune_log(void)
{
    char cutoff[32];
    char msg[64];
    time_t limit;
    struct tm tm;
    struct stat st;
    char *buf;
    size_t size, off = 0;
    const char *nl;
    int fd;

    if (!g_log_path) {
        return;
    }
    fd = open(g_log_path, O_RDWR);
    if (fd < 0) {
        return;
    }
    if (fstat(fd, &st) != 0 || st.st_size <= 0 ||
        st.st_size > kMaxPruneBytes) {
        close(fd);
        return;
    }
    size = (size_t)st.st_size;
    buf = malloc(size);
    if (!buf || read_all(fd, buf, size) != 0) {
        free(buf);
        close(fd);
        return;
    }

    limit = time(NULL) - kKeepSeconds;
    localtime_r(&limit, &tm);
    strftime(cutoff, sizeof cutoff, "%Y-%m-%d %H:%M:%S", &tm);

    while (off < size) {
        if (has_timestamp(buf + off, size - off) &&
            memcmp(buf + off, cutoff, 19) >= 0) {
            break;
        }
        nl = memchr(buf + off, '\n', size - off);
        off = nl ? (size_t)(nl - buf) + 1 : size;
    }

    if (off > 0) {
        if (write_all(fd, buf + off, size - off) == 0 &&
            ftruncate(fd, (off_t)(size - off)) == 0) {
            snprintf(msg, sizeof msg, "log pruned, %zu bytes cut", off);
            free(buf);
            close(fd);
            logf_line(msg, "prune");
            return;
        }
    }
    free(buf);
    close(fd);
}

static int read_lid(void)
{
    CFTypeRef value;
    int lid = LID_UNKNOWN;

    value = IORegistryEntryCreateCFProperty(g_root,
        CFSTR(kAppleClamshellStateKey), kCFAllocatorDefault, 0);
    if (!value) {
        return LID_UNKNOWN;
    }
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
        lid = CFBooleanGetValue(value) ? LID_CLOSED : LID_OPEN;
    }
    CFRelease(value);
    return lid;
}

static void lock_screen(void)
{
    char *argv[] = { "/usr/bin/pmset", "displaysleepnow", NULL };
    pid_t pid;
    int status;
    int rc;

    rc = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc != 0) {
        logf_line("pmset spawn failed", "lock");
        return;
    }
    if (waitpid(pid, &status, 0) < 0 || !WIFEXITED(status) ||
        WEXITSTATUS(status) != 0) {
        logf_line("pmset displaysleepnow failed", "lock");
    }
}

static int paused(void)
{
    const char *home = getenv("HOME");
    char path[1024];

    if (!home) {
        return 0;
    }
    if (snprintf(path, sizeof path, "%s%s", home, kPausedFile) >=
        (int)sizeof path) {
        return 0;
    }
    return access(path, F_OK) == 0;
}

/* Locks only on a known open-to-closed change, unless paused. */
static void update_lid(int lid, const char *source)
{
    int prev = g_lid;

    if (lid == LID_UNKNOWN || lid == prev) {
        return;
    }
    g_lid = lid;
    prune_log();
    if (lid == LID_CLOSED) {
        if (prev != LID_OPEN) {
            logf_line("lid closed", source);
        } else if (paused()) {
            logf_line("lid closed, paused, no lock", source);
        } else {
            logf_line("lid closed, lock", source);
            lock_screen();
        }
    } else {
        logf_line("lid open", source);
    }
}

static void on_message(void *refcon, io_service_t service,
                       uint32_t type, void *arg)
{
    (void)refcon;
    (void)service;

    if (type != kIOPMMessageClamshellStateChange) {
        return;
    }
    update_lid(((uintptr_t)arg & kClamshellStateBit) ? LID_CLOSED : LID_OPEN,
               "event");
}

/* Treat errors as active media: never lock when playback is uncertain. */
static int audio_playing(void)
{
    AudioObjectPropertyAddress devices_addr = {
        kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectPropertyAddress streams_addr = {
        kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    AudioObjectPropertyAddress running_addr = {
        kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 size = 0, count, i, running, streams_size;
    AudioDeviceID *devices;
    int active = 0;

    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &devices_addr,
            0, NULL, &size) != noErr || !size) return 1;
    devices = malloc(size);
    if (!devices) return 1;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &devices_addr,
            0, NULL, &size, devices) != noErr) {
        free(devices);
        return 1;
    }
    count = size / sizeof *devices;
    for (i = 0; i < count; i++) {
        streams_size = 0;
        if (AudioObjectGetPropertyDataSize(devices[i], &streams_addr, 0, NULL,
                &streams_size) != noErr) { active = 1; break; }
        if (!streams_size) continue;
        size = sizeof running;
        if (AudioObjectGetPropertyData(devices[i], &running_addr, 0, NULL,
                &size, &running) != noErr || running) { active = 1; break; }
    }
    free(devices);
    return active;
}

static int display_sleep_prevented(void)
{
    CFDictionaryRef assertions = NULL;
    CFNumberRef value;
    int level = 0;
    if (IOPMCopyAssertionsStatus(&assertions) != kIOReturnSuccess || !assertions)
        return 1;
    value = CFDictionaryGetValue(assertions,
        kIOPMAssertionTypePreventUserIdleDisplaySleep);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID() ||
        !CFNumberGetValue(value, kCFNumberIntType, &level)) level = 1;
    CFRelease(assertions);
    return level != 0;
}

static void check_idle(void)
{
    double idle = CGEventSourceSecondsSinceLastEventType(
        kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
    if (idle < kIdleSeconds) {
        g_idle_locked = 0;
        return;
    }
    if (!g_idle_locked && !audio_playing() && !display_sleep_prevented()) {
        logf_line("idle for 5 minutes, lock", "idle");
        lock_screen();
        g_idle_locked = 1;
    }
}

static void on_poll(CFRunLoopTimerRef timer, void *info)
{
    (void)timer;
    (void)info;
    update_lid(read_lid(), "poll");
    check_idle();
}

/* Writes after a prune must go to the new end, not the old offset. */
static void append_mode(int fd)
{
    int flags = fcntl(fd, F_GETFL);

    if (flags >= 0 && !(flags & O_APPEND)) {
        fcntl(fd, F_SETFL, flags | O_APPEND);
    }
}

int main(int argc, char **argv)
{
    IONotificationPortRef port;
    io_object_t notifier;
    CFRunLoopTimerRef timer;
    kern_return_t kr;

    if (argc > 1) {
        g_log_path = argv[1];
    }
    append_mode(STDOUT_FILENO);
    append_mode(STDERR_FILENO);
    prune_log();

    g_root = IOServiceGetMatchingService(kIOMainPortDefault,
        IOServiceMatching("IOPMrootDomain"));
    if (!g_root) {
        fprintf(stderr, "mac_lid_lock: IOPMrootDomain not found\n");
        return 1;
    }

    port = IONotificationPortCreate(kIOMainPortDefault);
    if (!port) {
        fprintf(stderr, "mac_lid_lock: IONotificationPortCreate failed\n");
        return 1;
    }
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
        IONotificationPortGetRunLoopSource(port), kCFRunLoopDefaultMode);

    kr = IOServiceAddInterestNotification(port, g_root, kIOGeneralInterest,
        on_message, NULL, &notifier);
    if (kr != KERN_SUCCESS) {
        fprintf(stderr, "mac_lid_lock: IOServiceAddInterestNotification "
                "failed: 0x%x\n", kr);
        return 1;
    }

    /* A lid that is closed at start is not a new close, so no lock. */
    g_lid = read_lid();
    logf_line(g_lid == LID_CLOSED ? "start, lid closed"
              : g_lid == LID_OPEN ? "start, lid open"
              : "start, lid unknown", "start");

    timer = CFRunLoopTimerCreate(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent() + kPollSeconds, kPollSeconds, 0, 0,
        on_poll, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);

    CFRunLoopRun();
    return 0;
}
