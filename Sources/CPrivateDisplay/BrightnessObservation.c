// DisplayServices notification pattern: emin93/ddc-mirror (MIT), see NOTICE.
#include "PrivateDisplay.h"
#include <dlfcn.h>
#include <stdatomic.h>
typedef void (*Handler)(void);
static _Atomic(Handler) handler;
static CGDirectDisplayID observed;
static void changed(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {
    Handler h = atomic_load(&handler);
    if (h) h();
}
void BRUnwatchBrightness(void) {
    atomic_store(&handler, NULL);
    int (*unreg)(uint32_t,uint32_t) = dlsym(RTLD_DEFAULT, "DisplayServicesUnregisterForBrightnessChangeNotifications");
    if (observed && unreg) unreg(observed, observed);
    observed = 0;
}
int32_t BRWatchBrightness(void (*cb)(void)) {
    BRUnwatchBrightness();
    int (*reg)(uint32_t,uint32_t,CFNotificationCallback) = dlsym(RTLD_DEFAULT, "DisplayServicesRegisterForBrightnessChangeNotifications");
    if (!reg || !dlsym(RTLD_DEFAULT, "DisplayServicesUnregisterForBrightnessChangeNotifications")) return -1;
    CGDirectDisplayID ids[32]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, ids, &count) != kCGErrorSuccess) return -2;
    for (uint32_t i=0; i<count; ++i) if (CGDisplayIsBuiltin(ids[i])) {
        atomic_store(&handler, cb);
        int rc = reg(ids[i], ids[i], changed);
        if (!rc) observed = ids[i]; else atomic_store(&handler, NULL);
        return rc;
    }
    return -3;
}
