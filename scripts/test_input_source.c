#include <Carbon/Carbon.h>
#include <stdio.h>

// Test-runner helper: query/select via TIS without changing enabled input sources.
int main(int argc, char **argv) {
    if (argc == 2) {
        CFStringRef wanted = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
        CFArrayRef list = TISCreateInputSourceList(NULL, false);
        OSStatus result = -1;
        for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
            TISInputSourceRef source = (TISInputSourceRef) CFArrayGetValueAtIndex(list, i);
            CFStringRef identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
            if (identifier && CFEqual(identifier, wanted)) { result = TISSelectInputSource(source); break; }
        }
        CFRelease(list);
        CFRelease(wanted);
        if (result != noErr) return 2;
    }
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    CFStringRef identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    char output[512];
    if (!identifier || !CFStringGetCString(identifier, output, sizeof(output), kCFStringEncodingUTF8)) return 3;
    puts(output);
    CFRelease(source);
    return 0;
}
