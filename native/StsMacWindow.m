// Native Cocoa bridge for the Slay the Spire macOS port.
//
// Responsibilities:
//   * keep the standard macOS window buttons working (green = native fullscreen)
//   * restore the last window frame / fullscreen state across launches
//   * expose the real Cocoa drawable size to the HiDPI-aware LWJGL overlay
//   * pause the OpenAL device while the app is in the background
#import <Cocoa/Cocoa.h>
#import <jni.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>

typedef struct ALCcontext_struct ALCcontext;
typedef struct ALCdevice_struct ALCdevice;
typedef char ALCboolean;
typedef ALCcontext *(*PFN_alcGetCurrentContext)(void);
typedef ALCdevice *(*PFN_alcGetContextsDevice)(ALCcontext *);
typedef ALCboolean (*PFN_alcDevicePauseSOFT)(ALCdevice *, ALCboolean);

static const NSInteger stsPrefsVersion = 2;

static void stsRunOnMain(dispatch_block_t block) {
    if ([NSThread isMainThread]) block(); else dispatch_sync(dispatch_get_main_queue(), block);
}

static NSUserDefaults *stsDefaults(void) {
    static NSUserDefaults *defaults;
    if (!defaults) defaults = [[NSUserDefaults alloc] initWithSuiteName:@"io.github.noahhhi.sts-modern"];
    return defaults;
}

static BOOL stsIsFullscreen(NSWindow *window) {
    return window != nil && ([window styleMask] & NSWindowStyleMaskFullScreen) != 0;
}

// The process also owns the ModTheSpire selector window and several hidden
// GLFW helper windows. Only the actual game window may drive saved geometry.
static BOOL stsIsGameWindow(NSWindow *window) {
    if (window == nil || ![window isVisible]) return NO;
    NSString *title = [window title];
    if (title.length == 0) return NO;
    return [title rangeOfString:@"slay the spire" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSWindow *stsFindWindow(void) {
    NSApplication *app = [NSApplication sharedApplication];
    NSWindow *fallback = nil;
    for (NSWindow *candidate in [app windows]) {
        if (!stsIsGameWindow(candidate)) continue;
        if (stsIsFullscreen(candidate)) return candidate;
        if (fallback == nil || [candidate frame].size.width > [fallback frame].size.width) {
            fallback = candidate;
        }
    }
    if (fallback != nil) return fallback;
    NSWindow *window = [app mainWindow];
    if (stsIsGameWindow(window)) return window;
    window = [app keyWindow];
    if (stsIsGameWindow(window)) return window;
    return nil;
}

static BOOL stsFrameIsUsable(NSRect rect) {
    if (rect.size.width < 800 || rect.size.height < 450) return NO;
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y)) return NO;
    for (NSScreen *screen in [NSScreen screens]) {
        NSRect visible = [screen visibleFrame];
        NSRect overlap = NSIntersectionRect(rect, visible);
        if (overlap.size.width >= 400 && overlap.size.height >= 300) return YES;
    }
    return NO;
}

static void stsSaveFrame(NSWindow *window) {
    if (window == nil || !stsIsGameWindow(window) || stsIsFullscreen(window)) return;
    NSRect frame = [window frame];
    if (!stsFrameIsUsable(frame)) return;
    [stsDefaults() setObject:NSStringFromRect(frame) forKey:@"sts.windowFrame"];
}

static void stsDiagnostics(NSWindow *window, const char *stage) {
    if (window == nil) {
        fprintf(stderr, "[STSWIN] %s window=nil\n", stage);
        return;
    }
    NSRect frame = [window frame];
    NSRect content = [[window contentView] bounds];
    NSRect layout = [window contentLayoutRect];
    NSScreen *screen = [window screen];
    CGFloat safeTop = 0;
    if (@available(macOS 12.0, *)) {
        if (screen != nil) safeTop = [screen safeAreaInsets].top;
    }
    fprintf(stderr,
            "[STSWIN] %s title=%s frame=%.0fx%.0f content=%.0fx%.0f layout=%.0fx%.0f "
            "styleMask=0x%lx collectionBehavior=0x%lx fullscreen=%d screen=%.0fx%.0f safeTop=%.0f\n",
            stage, [[window title] UTF8String], frame.size.width, frame.size.height,
            content.size.width, content.size.height, layout.size.width, layout.size.height,
            (unsigned long)[window styleMask], (unsigned long)[window collectionBehavior],
            (int)stsIsFullscreen(window), screen ? [screen frame].size.width : 0,
            screen ? [screen frame].size.height : 0, safeTop);
}

#pragma mark - Background audio pause

static void *stsOpenALHandle(void) {
    static void *handle;
    static BOOL searched;
    if (searched) return handle;
    searched = YES;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name == NULL) continue;
        if (strstr(name, "openal") == NULL && strstr(name, "OpenAL") == NULL) continue;
        handle = dlopen(name, RTLD_LAZY | RTLD_NOLOAD);
        if (handle != NULL) break;
    }
    return handle;
}

static void stsSetAudioPaused(BOOL pause) {
    static BOOL current = NO;
    static BOOL resolved = NO;
    static PFN_alcGetCurrentContext getContext;
    static PFN_alcGetContextsDevice getDevice;
    static PFN_alcDevicePauseSOFT pauseDevice;
    if (pause == current) return;
    if (!resolved) {
        resolved = YES;
        void *handle = stsOpenALHandle();
        if (handle != NULL) {
            getContext = (PFN_alcGetCurrentContext)dlsym(handle, "alcGetCurrentContext");
            getDevice = (PFN_alcGetContextsDevice)dlsym(handle, "alcGetContextsDevice");
            pauseDevice = (PFN_alcDevicePauseSOFT)dlsym(handle, "alcDevicePauseSOFT");
        }
    }
    if (getContext == NULL || getDevice == NULL || pauseDevice == NULL) return;
    ALCcontext *context = getContext();
    if (context == NULL) return;
    ALCdevice *device = getDevice(context);
    if (device == NULL) return;
    pauseDevice(device, pause ? 1 : 0);
    current = pause;
    fprintf(stderr, "[STSWIN] audio %s\n", pause ? "paused" : "resumed");
}

#pragma mark - Observers

static void stsInstallObservers(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:NSWindowDidEnterFullScreenNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        NSWindow *window = [note object];
                        if (!stsIsGameWindow(window)) return;
                        [stsDefaults() setBool:YES forKey:@"sts.wasFullscreen"];
                        stsDiagnostics(window, "entered-fullscreen");
                    }];
    [center addObserverForName:NSWindowDidExitFullScreenNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        NSWindow *window = [note object];
                        if (!stsIsGameWindow(window)) return;
                        [stsDefaults() setBool:NO forKey:@"sts.wasFullscreen"];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{ stsSaveFrame(window); });
                        stsDiagnostics(window, "exited-fullscreen");
                    }];
    [center addObserverForName:NSWindowDidMoveNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { stsSaveFrame([note object]); }];
    [center addObserverForName:NSWindowDidResizeNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { stsSaveFrame([note object]); }];
    [center addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        stsSetAudioPaused(YES);
                        [stsDefaults() synchronize];
                    }];
    [center addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) { stsSetAudioPaused(NO); }];
    [center addObserverForName:NSApplicationWillTerminateNotification object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        stsSaveFrame(stsFindWindow());
                        [stsDefaults() synchronize];
                    }];
}

#pragma mark - JNI entry points

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)vm;
    (void)reserved;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL Java_com_megacrit_cardcrawl_desktop_StsWindow_nativeApplyStartup
  (JNIEnv *env, jclass cls) {
    (void)env;
    (void)cls;
    stsRunOnMain(^{
        stsInstallObservers();
        NSUserDefaults *defaults = stsDefaults();
        // v1.2.10 and older could record a tiny helper window (160x160) as the
        // game frame. Reset those stale values exactly once.
        if ([defaults integerForKey:@"sts.prefsVersion"] < stsPrefsVersion) {
            [defaults removeObjectForKey:@"sts.windowFrame"];
            [defaults removeObjectForKey:@"sts.wasFullscreen"];
            [defaults setInteger:stsPrefsVersion forKey:@"sts.prefsVersion"];
        }
        NSWindow *window = stsFindWindow();
        if (window == nil) {
            fprintf(stderr, "[STSWIN] startup: game window not found yet\n");
            return;
        }
        [window setCollectionBehavior:([window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary)];
        NSRect frame = NSRectFromString([defaults stringForKey:@"sts.windowFrame"] ?: @"");
        if (stsFrameIsUsable(frame)) {
            [window setFrame:frame display:YES];
        }
        stsDiagnostics(window, "startup");
        BOOL wantFullscreen = [defaults boolForKey:@"sts.wasFullscreen"];
        if (wantFullscreen) {
            NSWindow *target = window;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               if (!stsIsFullscreen(target)) {
                                   [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
                                   [target makeKeyAndOrderFront:nil];
                                   [target toggleFullScreen:nil];
                                   fprintf(stderr, "[STSWIN] restoring fullscreen\n");
                               }
                           });
        }
    });
}

JNIEXPORT jintArray JNICALL Java_com_megacrit_cardcrawl_desktop_StsWindow_nativeDrawableSize
  (JNIEnv *env, jclass cls) {
    (void)cls;
    static jint values[2];
    values[0] = 0;
    values[1] = 0;
    stsRunOnMain(^{
        NSWindow *window = stsFindWindow();
        if (window == nil) return;
        NSView *view = [window contentView];
        NSRect backing = [view convertRectToBacking:[view bounds]];
        values[0] = (jint)backing.size.width;
        values[1] = (jint)backing.size.height;
    });
    jintArray result = (*env)->NewIntArray(env, 2);
    (*env)->SetIntArrayRegion(env, result, 0, 2, values);
    return result;
}

JNIEXPORT void JNICALL Java_com_megacrit_cardcrawl_desktop_StsWindow_nativeToggleFullscreen
  (JNIEnv *env, jclass cls) {
    (void)env;
    (void)cls;
    stsRunOnMain(^{
        NSWindow *window = stsFindWindow();
        if (window == nil) return;
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:nil];
        [window toggleFullScreen:nil];
    });
}

JNIEXPORT jboolean JNICALL Java_com_megacrit_cardcrawl_desktop_StsWindow_nativeIsFullscreen
  (JNIEnv *env, jclass cls) {
    (void)env;
    (void)cls;
    static BOOL value;
    stsRunOnMain(^{ value = stsIsFullscreen(stsFindWindow()); });
    return value ? JNI_TRUE : JNI_FALSE;
}
