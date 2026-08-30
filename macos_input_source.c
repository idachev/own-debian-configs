#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

static const char kUsId[] = "com.apple.keylayout.US";

static void usage(void)
{
    fprintf(stderr, "usage: macos_input_source [us]\n");
}

static int current_id(char *buf, size_t n)
{
    TISInputSourceRef cur;
    CFStringRef id;
    int rc = 1;

    cur = TISCopyCurrentKeyboardInputSource();
    if (!cur) {
        return 1;
    }
    id = TISGetInputSourceProperty(cur, kTISPropertyInputSourceID);
    if (id && CFStringGetCString(id, buf, (CFIndex)n, kCFStringEncodingUTF8)) {
        rc = 0;
    }
    CFRelease(cur);
    return rc;
}

static int select_id(const char *wanted)
{
    char now[256];
    CFStringRef wanted_cf;
    const void *keys[1];
    const void *vals[1];
    CFDictionaryRef filter;
    CFArrayRef list;
    TISInputSourceRef src;
    OSStatus st;

    if (current_id(now, sizeof now) == 0 && strcmp(now, wanted) == 0) {
        return 0;
    }

    wanted_cf = CFStringCreateWithCString(NULL, wanted, kCFStringEncodingUTF8);
    if (!wanted_cf) {
        return 1;
    }
    keys[0] = kTISPropertyInputSourceID;
    vals[0] = wanted_cf;
    filter = CFDictionaryCreate(NULL, keys, vals, 1,
                                &kCFTypeDictionaryKeyCallBacks,
                                &kCFTypeDictionaryValueCallBacks);
    CFRelease(wanted_cf);
    if (!filter) {
        return 1;
    }

    list = TISCreateInputSourceList(filter, false);
    CFRelease(filter);
    if (!list || CFArrayGetCount(list) < 1) {
        if (list) {
            CFRelease(list);
        }
        return 1;
    }

    src = (TISInputSourceRef)CFArrayGetValueAtIndex(list, 0);
    st = TISSelectInputSource(src);
    CFRelease(list);
    return st == noErr ? 0 : 1;
}

int main(int argc, char **argv)
{
    char buf[256];

    if (argc == 1) {
        if (current_id(buf, sizeof buf) != 0) {
            return 1;
        }
        puts(buf);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "us") == 0) {
        return select_id(kUsId);
    }
    usage();
    return 2;
}
