/* Remap the NoMachine ISO key (LSGT: ѝ / <) to ч and ~.
 *
 * NoMachine injects keys through the XTEST keyboard. The laptop keyboard
 * is a different device and keeps ѝ / <.
 *
 * While LSGT is grabbed, XTEST injection of another key is swallowed.
 * On each press the grab is dropped, key SPARE is tapped, then the grab
 * is armed again. SPARE is an otherwise unused keycode.
 *
 *   gcc -O2 -o nomachine-che-tilde nomachine-che-tilde.c -lX11 -lXi -lXtst
 */
#include <X11/XKBlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XInput2.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>

#include <errno.h>
#include <fcntl.h>
#include <locale.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define SPARE_KC 248

static FILE *g_log;
static int g_lsgt_kc = 94;
static int g_xtest_id = -1;
static int g_xi_opcode;

static void log_msg(const char *text)
{
    time_t now = time(NULL);
    struct tm tm;
    char stamp[32];

    localtime_r(&now, &tm);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tm);
    if (!g_log) {
        const char *home = getenv("HOME");
        char path[512];
        if (!home) return;
        snprintf(path, sizeof(path), "%s/.cache/nomachine-che-tilde.log", home);
        g_log = fopen(path, "a");
        if (!g_log) return;
        setvbuf(g_log, NULL, _IOLBF, 0);
    }
    fprintf(g_log, "%s %s\n", stamp, text);
}

static int x_error(Display *dpy, XErrorEvent *err)
{
    char buf[128];
    char msg[256];
    (void)dpy;
    XGetErrorText(err->display, err->error_code, buf, sizeof(buf));
    snprintf(msg, sizeof(msg), "X error %s major %u minor %u",
             buf, err->request_code, err->minor_code);
    log_msg(msg);
    return 0;
}

static int spare_ready(Display *dpy)
{
    XkbDescPtr desc;
    XkbSymMapPtr map;
    KeySym *syms;
    int groups;

    desc = XkbGetMap(dpy, XkbAllClientInfoMask, XkbUseCoreKbd);
    if (!desc || !desc->map) return 0;
    map = &desc->map->key_sym_map[SPARE_KC];
    groups = XkbNumGroups(map->group_info);
    if (map->width < 2 || groups < 1) {
        XkbFreeKeyboard(desc, 0, True);
        return 0;
    }
    syms = desc->map->syms + map->offset;
    groups = syms[0] == XK_Cyrillic_che && syms[1] == XK_asciitilde;
    XkbFreeKeyboard(desc, 0, True);
    return groups;
}

/* xkbcomp keeps the normal <> key. XkbSetMap does not stick on this server. */
static int install_spare(Display *dpy)
{
    XkbStateRec st;
    int group = 0;
    const char *script;
    char cmd[512];
    int rc;

    if (spare_ready(dpy)) return 1;
    if (XkbGetState(dpy, XkbUseCoreKbd, &st) == Success) group = st.locked_group;
    script = getenv("NOMACHINE_CHE_TILDE_MAP");
    if (!script || !script[0]) script = "/home/idachev/bin/nomachine-che-tilde-map.sh";
    snprintf(cmd, sizeof(cmd), "%s", script);
    rc = system(cmd);
    XkbLockGroup(dpy, XkbUseCoreKbd, group);
    XFlush(dpy);
    if (rc != 0 || !spare_ready(dpy)) {
        log_msg("could not install ч / ~");
        return 0;
    }
    log_msg("spare key is ч / ~");
    return 1;
}

static int find_xtest(Display *dpy)
{
    int n = 0;
    int id = -1;
    int i;
    XIDeviceInfo *devs = XIQueryDevice(dpy, XIAllDevices, &n);

    if (!devs) return -1;
    for (i = 0; i < n; i++) {
        if (devs[i].use == XISlaveKeyboard && devs[i].name &&
            strcmp(devs[i].name, "Virtual core XTEST keyboard") == 0)
            id = devs[i].deviceid;
    }
    XIFreeDeviceInfo(devs);
    return id;
}

static int arm_grab(Display *dpy)
{
    unsigned char bits[4];
    XIEventMask mask;
    XIGrabModifiers mods;
    int rc;

    memset(bits, 0, sizeof(bits));
    mask.deviceid = g_xtest_id;
    mask.mask_len = sizeof(bits);
    mask.mask = bits;
    XISetMask(bits, XI_KeyPress);
    XISetMask(bits, XI_KeyRelease);
    mods.modifiers = XIAnyModifier;
    mods.status = 0;
    rc = XIGrabKeycode(dpy, g_xtest_id, g_lsgt_kc, DefaultRootWindow(dpy),
                       XIGrabModeAsync, XIGrabModeAsync, False, &mask, 1, &mods);
    /* A second grab while we already hold it is fine. Cinnamon reloads drop it. */
    if (rc == 0 && (mods.status == GrabSuccess || mods.status == AlreadyGrabbed))
        return 1;
    {
        char buf[80];
        snprintf(buf, sizeof(buf), "grab failed rc %d status %d", rc, mods.status);
        log_msg(buf);
    }
    return 0;
}

static void tap_spare(Display *dpy)
{
    struct timespec gap = {0, 8000000};

    XTestFakeKeyEvent(dpy, SPARE_KC, True, CurrentTime);
    XFlush(dpy);
    nanosleep(&gap, NULL);
    XTestFakeKeyEvent(dpy, SPARE_KC, False, CurrentTime);
    XFlush(dpy);
}

static void on_lsgt_press(Display *dpy)
{
    /* The active grab would swallow a second XTEST key. Drop it first. */
    XIUngrabDevice(dpy, g_xtest_id, CurrentTime);
    XFlush(dpy);
    tap_spare(dpy);
    arm_grab(dpy);
    XFlush(dpy);
}

static int take_lock(void)
{
    const char *base = getenv("XDG_RUNTIME_DIR");
    char path[512];
    int fd;

    if (!base || !base[0]) base = "/tmp";
    snprintf(path, sizeof(path), "%s/nomachine-che-tilde.lock", base);
    fd = open(path, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return -1;
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static void run_service(void)
{
    Display *dpy;
    int event, error;
    int lock_fd;

    lock_fd = take_lock();
    if (lock_fd < 0) {
        log_msg("already running");
        return;
    }
    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        log_msg("no display");
        return;
    }
    XSetErrorHandler(x_error);
    if (!XQueryExtension(dpy, "XInputExtension", &g_xi_opcode, &event, &error)) {
        log_msg("no XInput");
        return;
    }
    if (!install_spare(dpy)) return;
    g_xtest_id = find_xtest(dpy);
    if (g_xtest_id < 0) {
        log_msg("no XTEST keyboard");
        return;
    }
    if (!arm_grab(dpy)) return;
    XFlush(dpy);
    log_msg("listening");

    for (;;) {
        fd_set rfds;
        struct timeval tv;
        int xfd = ConnectionNumber(dpy);

        tv.tv_sec = 2;
        tv.tv_usec = 0;
        FD_ZERO(&rfds);
        FD_SET(xfd, &rfds);
        if (select(xfd + 1, &rfds, NULL, NULL, &tv) > 0) {
            while (XPending(dpy)) {
                XEvent ev;
                XNextEvent(dpy, &ev);
                if (ev.type != GenericEvent || ev.xcookie.extension != g_xi_opcode)
                    continue;
                if (!XGetEventData(dpy, &ev.xcookie)) continue;
                if (ev.xcookie.evtype == XI_KeyPress) {
                    XIDeviceEvent *dev = ev.xcookie.data;
                    if (dev->detail == g_lsgt_kc && !(dev->flags & XIKeyRepeat)) {
                        if (!spare_ready(dpy)) install_spare(dpy);
                        on_lsgt_press(dpy);
                    }
                }
                XFreeEventData(dpy, &ev.xcookie);
            }
        }
        /* Re-arm only. Reloading the map here fights Cinnamon. */
        arm_grab(dpy);
    }
}

static int wait_key(Display *dpy, Window win, XIC xic, int *keycode, KeySym *ks,
                    char *text, size_t text_len)
{
    double deadline;
    struct timespec ts;
    struct timespec sl = {0, 5000000};

    clock_gettime(CLOCK_MONOTONIC, &ts);
    deadline = ts.tv_sec + ts.tv_nsec / 1e9 + 0.6;
    while (1) {
        clock_gettime(CLOCK_MONOTONIC, &ts);
        if (ts.tv_sec + ts.tv_nsec / 1e9 > deadline) return 0;
        while (XPending(dpy)) {
            XEvent ev;
            XNextEvent(dpy, &ev);
            if (ev.type == KeyPress && ev.xkey.window == win) {
                Status st;
                int n;
                *keycode = ev.xkey.keycode;
                *ks = 0;
                text[0] = 0;
                if (xic) {
                    n = Xutf8LookupString(xic, &ev.xkey, text, (int)text_len - 1, ks, &st);
                    if (n < 0) n = 0;
                    text[n] = 0;
                } else {
                    n = XLookupString(&ev.xkey, text, (int)text_len - 1, ks, NULL);
                    if (n < 0) n = 0;
                    text[n] = 0;
                }
                if (*ks == XK_Shift_L || *ks == XK_Shift_R) continue;
                return 1;
            }
        }
        nanosleep(&sl, NULL);
    }
}

static int run_check(void)
{
    Display *dpy;
    int screen;
    XSetWindowAttributes attr;
    Window win;
    XIM xim = NULL;
    XIC xic = NULL;
    KeyCode shift;
    int kc = 0;
    KeySym ks = 0;
    char text[16];
    int leaks = 0;
    int che_ok = 0;
    int tilde_ok = 0;
    KeySym lsgt_bg;

    dpy = XOpenDisplay(NULL);
    if (!dpy) return 1;
    screen = DefaultScreen(dpy);
    attr.override_redirect = True;
    attr.event_mask = KeyPressMask | KeyReleaseMask;
    win = XCreateWindow(dpy, RootWindow(dpy, screen), 0, 0, 8, 8, 0,
                        CopyFromParent, InputOnly, CopyFromParent,
                        CWOverrideRedirect | CWEventMask, &attr);
    XMapWindow(dpy, win);
    XFlush(dpy);
    {
        struct timespec pause = {0, 30000000};
        nanosleep(&pause, NULL);
    }
    if (XGrabKeyboard(dpy, win, True, GrabModeAsync, GrabModeAsync,
                      CurrentTime) != GrabSuccess) {
        fprintf(stderr, "keyboard grab failed\n");
        return 2;
    }

    setlocale(LC_ALL, "");
    xim = XOpenIM(dpy, NULL, NULL, NULL);
    if (xim) {
        xic = XCreateIC(xim, XNInputStyle, XIMPreeditNothing | XIMStatusNothing,
                        XNClientWindow, win, NULL);
    }

    shift = XKeysymToKeycode(dpy, XK_Shift_L);
    {
        int attempt;
        for (attempt = 0; attempt < 8 && !che_ok; attempt++) {
            XTestFakeKeyEvent(dpy, g_lsgt_kc, True, CurrentTime);
            XTestFakeKeyEvent(dpy, g_lsgt_kc, False, CurrentTime);
            XFlush(dpy);
            if (!wait_key(dpy, win, xic, &kc, &ks, text, sizeof(text))) {
                fprintf(stderr, "plain: no key\n");
                continue;
            }
            fprintf(stderr, "plain kc %d ks %#lx text '%s'\n",
                    kc, (unsigned long)ks, text);
            if (kc == SPARE_KC && ks == XK_Cyrillic_che && strcmp(text, "ч") == 0)
                che_ok = 1;
        }
    }

    XTestFakeKeyEvent(dpy, shift, True, CurrentTime);
    XFlush(dpy);
    {
        struct timespec pause = {0, 40000000};
        double deadline;
        struct timespec now;
        nanosleep(&pause, NULL);
        clock_gettime(CLOCK_MONOTONIC, &now);
        deadline = now.tv_sec + now.tv_nsec / 1e9 + 0.05;
        while (now.tv_sec + now.tv_nsec / 1e9 < deadline) {
            while (XPending(dpy)) {
                XEvent ev;
                XNextEvent(dpy, &ev);
            }
            nanosleep(&pause, NULL);
            clock_gettime(CLOCK_MONOTONIC, &now);
        }
    }
    XTestFakeKeyEvent(dpy, g_lsgt_kc, True, CurrentTime);
    XTestFakeKeyEvent(dpy, g_lsgt_kc, False, CurrentTime);
    XFlush(dpy);
    if (wait_key(dpy, win, xic, &kc, &ks, text, sizeof(text))) {
        fprintf(stderr, "shift kc %d ks %#lx text '%s'\n", kc, (unsigned long)ks, text);
        if (kc == g_lsgt_kc) leaks++;
        if (kc == SPARE_KC && ks == XK_asciitilde && strcmp(text, "~") == 0)
            tilde_ok = 1;
    } else {
        fprintf(stderr, "shift: no key\n");
    }
    XTestFakeKeyEvent(dpy, shift, False, CurrentTime);
    XTestFakeKeyEvent(dpy, SPARE_KC, False, CurrentTime);
    XFlush(dpy);

    lsgt_bg = XkbKeycodeToKeysym(dpy, g_lsgt_kc, 1, 0);
    fprintf(stderr, "che_ok=%d tilde_ok=%d leaks=%d lsgt_bg=%#lx\n",
            che_ok, tilde_ok, leaks, (unsigned long)lsgt_bg);
    XUngrabKeyboard(dpy, CurrentTime);
    XFlush(dpy);
    XCloseDisplay(dpy);
    return (che_ok && tilde_ok && leaks == 0 && lsgt_bg == 0x100045d) ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        pid_t pid = fork();
        int rc;
        if (pid < 0) return 1;
        if (pid == 0) {
            usleep(100000);
            run_service();
            _exit(0);
        }
        usleep(300000);
        rc = run_check();
        kill(pid, SIGTERM);
        waitpid(pid, NULL, 0);
        {
            Display *dpy = XOpenDisplay(NULL);
            if (dpy) {
                XTestFakeKeyEvent(dpy, SPARE_KC, False, CurrentTime);
                XFlush(dpy);
                XCloseDisplay(dpy);
            }
        }
        return rc;
    }
    run_service();
    return 0;
}
