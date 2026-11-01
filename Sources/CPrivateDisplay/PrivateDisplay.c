// The per-display Apple Silicon DDC routing and packet format are adapted from
// waydabber/m1ddc and MonitorControl (MIT License). See NOTICE.

#include "PrivateDisplay.h"

#include <IOKit/IOReturn.h>
#include <dlfcn.h>
#include <math.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

typedef CFTypeRef IOAVService;

extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator,
                                                 io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service,
                                   uint32_t chipAddress,
                                   uint32_t dataAddress,
                                   void *outputBuffer,
                                   uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service,
                                    uint32_t chipAddress,
                                    uint32_t dataAddress,
                                    void *inputBuffer,
                                    uint32_t inputBufferSize);
extern int DisplayServicesGetBrightness(CGDirectDisplayID display,
                                        float *brightness);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);
extern CFUUIDRef CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID display);

static const uint32_t kDefaultDDCChipAddress = 0x37;
static const uint32_t kMCDP29xxChipAddress = 0xB7;
static const uint32_t kDDCDataAddress = 0x51;
static const uint8_t kBrightnessVCPCode = 0x10;
#define BR_MAXIMUM_DISPLAYS 32
#define BR_CONNECTION_API_UNAVAILABLE -100
#define BR_CONNECTION_LAST_ACTIVE -101
#define BR_CONNECTION_DISPLAY_NOT_FOUND -102
#define BR_CONNECTION_AMBIGUOUS_DISPLAY -103
#define BR_CONNECTION_BEGIN_FAILED -104

typedef struct {
    IOAVService service;
    uint32_t chipAddress;
} BRDDCTransport;

static void BRCopyCFString(CFStringRef value, char *destination, size_t capacity) {
    if (destination == NULL || capacity == 0) {
        return;
    }
    destination[0] = '\0';
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) {
        return;
    }
    CFStringGetCString(value, destination, (CFIndex)capacity, kCFStringEncodingUTF8);
}

static CFTypeRef BRCopyRecursiveProperty(io_registry_entry_t entry, CFStringRef key) {
    return IORegistryEntrySearchCFProperty(
        entry,
        kIOServicePlane,
        key,
        kCFAllocatorDefault,
        kIORegistryIterateRecursively | kIORegistryIterateParents
    );
}

static bool BRCFBooleanValue(CFTypeRef value) {
    return value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() &&
        CFBooleanGetValue((CFBooleanRef)value);
}

static void BRPopulateDisplayAttributes(io_registry_entry_t adapter,
                                        BRExternalDisplayInfo *display) {
    CFTypeRef edid = BRCopyRecursiveProperty(adapter, CFSTR("EDID UUID"));
    if (edid != NULL) {
        BRCopyCFString((CFStringRef)edid, display->edidUUID, sizeof(display->edidUUID));
        CFRelease(edid);
    }

    CFTypeRef rawAttributes = BRCopyRecursiveProperty(adapter, CFSTR("DisplayAttributes"));
    if (rawAttributes == NULL || CFGetTypeID(rawAttributes) != CFDictionaryGetTypeID()) {
        if (rawAttributes != NULL) CFRelease(rawAttributes);
        return;
    }

    CFDictionaryRef attributes = (CFDictionaryRef)rawAttributes;
    display->supportsStandby = BRCFBooleanValue(
        CFDictionaryGetValue(attributes, CFSTR("SupportsStandby"))
    ) ? 1 : 0;

    CFTypeRef rawProduct = CFDictionaryGetValue(attributes, CFSTR("ProductAttributes"));
    if (rawProduct != NULL && CFGetTypeID(rawProduct) == CFDictionaryGetTypeID()) {
        CFTypeRef name = CFDictionaryGetValue((CFDictionaryRef)rawProduct, CFSTR("ProductName"));
        if (name != NULL && CFGetTypeID(name) == CFStringGetTypeID()) {
            BRCopyCFString((CFStringRef)name, display->name, sizeof(display->name));
        }
    }
    CFRelease(rawAttributes);
}

static void BRPopulateFallbackIdentity(BRExternalDisplayInfo *display) {
    if (display->name[0] == '\0') {
        snprintf(display->name, sizeof(display->name), "Display %u", display->displayID);
    }
    if (display->edidUUID[0] != '\0') {
        snprintf(display->stableID, sizeof(display->stableID), "%s", display->edidUUID);
        return;
    }

    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display->displayID);
    if (uuid != NULL) {
        CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        if (uuidString != NULL) {
            BRCopyCFString(uuidString, display->stableID, sizeof(display->stableID));
            CFRelease(uuidString);
        }
        CFRelease(uuid);
    }
    if (display->stableID[0] == '\0') {
        snprintf(
            display->stableID,
            sizeof(display->stableID),
            "%04X-%04X-%08X",
            display->vendorID,
            display->productID,
            display->serialNumber
        );
    }
}

int32_t BRDDCCopyExternalDisplays(BRExternalDisplayInfo *displays, uint32_t capacity) {
    uint32_t onlineCount = 0;
    if (CGGetOnlineDisplayList(0, NULL, &onlineCount) != kCGErrorSuccess || onlineCount == 0) {
        return 0;
    }
    if (onlineCount > BR_MAXIMUM_DISPLAYS) onlineCount = BR_MAXIMUM_DISPLAYS;

    CGDirectDisplayID onlineDisplays[BR_MAXIMUM_DISPLAYS];
    if (CGGetOnlineDisplayList(onlineCount, onlineDisplays, &onlineCount) != kCGErrorSuccess) {
        return -1;
    }

    uint32_t externalCount = 0;
    for (uint32_t index = 0; index < onlineCount; index += 1) {
        CGDirectDisplayID displayID = onlineDisplays[index];
        if (displayID == 0 || CGDisplayIsBuiltin(displayID) != 0) {
            continue;
        }

        BRExternalDisplayInfo info = {0};
        info.displayID = displayID;
        info.vendorID = CGDisplayVendorNumber(displayID);
        info.productID = CGDisplayModelNumber(displayID);
        info.serialNumber = CGDisplaySerialNumber(displayID);
        info.isMain = displayID == CGMainDisplayID() ? 1 : 0;

        CFDictionaryRef displayDictionary = CoreDisplay_DisplayCreateInfoDictionary(displayID);
        if (displayDictionary != NULL) {
            CFTypeRef location = CFDictionaryGetValue(displayDictionary, CFSTR("IODisplayLocation"));
            if (location != NULL && CFGetTypeID(location) == CFStringGetTypeID()) {
                BRCopyCFString((CFStringRef)location, info.ioLocation, sizeof(info.ioLocation));
                io_registry_entry_t adapter = IORegistryEntryCopyFromPath(
                    kIOMainPortDefault,
                    (CFStringRef)location
                );
                if (adapter != IO_OBJECT_NULL) {
                    BRPopulateDisplayAttributes(adapter, &info);
                    IOObjectRelease(adapter);
                }
            }
            CFRelease(displayDictionary);
        }
        BRPopulateFallbackIdentity(&info);

        if (displays != NULL && externalCount < capacity) {
            displays[externalCount] = info;
        }
        externalCount += 1;
    }
    return (int32_t)externalCount;
}

static bool BRIsMCDP29xxProxy(io_service_t proxy) {
    io_registry_entry_t parent = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) {
        return false;
    }
    CFTypeRef providerClass = IORegistryEntryCreateCFProperty(
        parent,
        CFSTR("EPICProviderClass"),
        kCFAllocatorDefault,
        0
    );
    bool isMCDP = providerClass != NULL &&
        CFGetTypeID(providerClass) == CFStringGetTypeID() &&
        CFStringCompare((CFStringRef)providerClass, CFSTR("AppleDCPMCDP29XX"), 0) ==
            kCFCompareEqualTo;
    if (providerClass != NULL) CFRelease(providerClass);
    IOObjectRelease(parent);
    return isMCDP;
}

static bool BRIsExternalService(io_service_t service) {
    CFTypeRef location = IORegistryEntryCreateCFProperty(
        service,
        CFSTR("Location"),
        kCFAllocatorDefault,
        kIORegistryIterateRecursively
    );
    bool isExternal = location != NULL &&
        CFGetTypeID(location) == CFStringGetTypeID() &&
        CFStringCompare((CFStringRef)location, CFSTR("External"), 0) == kCFCompareEqualTo;
    if (location != NULL) CFRelease(location);
    return isExternal;
}

static BRDDCTransport BRCreateTransport(CGDirectDisplayID displayID) {
    BRDDCTransport transport = {.service = NULL, .chipAddress = kDefaultDDCChipAddress};
    CFDictionaryRef displayDictionary = CoreDisplay_DisplayCreateInfoDictionary(displayID);
    if (displayDictionary == NULL) {
        return transport;
    }
    CFTypeRef location = CFDictionaryGetValue(displayDictionary, CFSTR("IODisplayLocation"));
    if (location == NULL || CFGetTypeID(location) != CFStringGetTypeID()) {
        CFRelease(displayDictionary);
        return transport;
    }

    io_registry_entry_t selectedAdapter = IORegistryEntryCopyFromPath(
        kIOMainPortDefault,
        (CFStringRef)location
    );
    CFRelease(displayDictionary);
    if (selectedAdapter == IO_OBJECT_NULL) {
        return transport;
    }

    uint64_t selectedAdapterID = 0;
    if (IORegistryEntryGetRegistryEntryID(selectedAdapter, &selectedAdapterID) != KERN_SUCCESS) {
        IOObjectRelease(selectedAdapter);
        return transport;
    }
    IOObjectRelease(selectedAdapter);

    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (root == IO_OBJECT_NULL) return transport;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t iteratorResult = IORegistryEntryCreateIterator(
        root,
        kIOServicePlane,
        kIORegistryIterateRecursively,
        &iterator
    );
    IOObjectRelease(root);
    if (iteratorResult != KERN_SUCCESS) return transport;

    bool framebufferMatches = false;
    io_service_t service = IO_OBJECT_NULL;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (IOObjectConformsTo(service, "IOMobileFramebuffer")) {
            uint64_t framebufferID = 0;
            framebufferMatches = IORegistryEntryGetRegistryEntryID(service, &framebufferID) ==
                    KERN_SUCCESS && framebufferID == selectedAdapterID;
            IOObjectRelease(service);
            continue;
        }

        io_name_t name = {0};
        bool isTarget = framebufferMatches &&
            IORegistryEntryGetName(service, name) == KERN_SUCCESS &&
            strcmp(name, "DCPAVServiceProxy") == 0 &&
            BRIsExternalService(service);
        if (!isTarget) {
            IOObjectRelease(service);
            continue;
        }

        transport.service = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        transport.chipAddress = BRIsMCDP29xxProxy(service)
            ? kMCDP29xxChipAddress
            : kDefaultDDCChipAddress;
        IOObjectRelease(service);
        break;
    }
    IOObjectRelease(iterator);
    return transport;
}

static uint8_t BRChecksum(uint8_t seed, const uint8_t *bytes, size_t count) {
    uint8_t checksum = seed;
    for (size_t index = 0; index < count; index += 1) {
        checksum ^= bytes[index];
    }
    return checksum;
}

static bool BRWriteVCP(BRDDCTransport transport, uint8_t code, uint16_t value) {
    uint8_t packet[6] = {
        0x84,
        0x03,
        code,
        (uint8_t)(value >> 8),
        (uint8_t)(value & 0xFF),
        0x00,
    };
    packet[5] = BRChecksum((uint8_t)(0x6E ^ kDDCDataAddress), packet, 5);

    for (int retry = 0; retry < 3; ++retry) {
        if (retry) usleep(251000);
        if (IOAVServiceWriteI2C(transport.service, transport.chipAddress, kDDCDataAddress,
                               packet, (uint32_t)sizeof(packet)) == KERN_SUCCESS) return true;
    }
    return false;
}

int32_t BRDDCWriteVCP(uint32_t displayID, uint8_t code, uint16_t value) {
    BRDDCTransport transport = BRCreateTransport(displayID);
    if (transport.service == NULL) return -2;
    bool success = BRWriteVCP(transport, code, value);
    CFRelease(transport.service);
    return success ? 0 : -3;
}

int32_t BRDisplayGetChromaticities(uint32_t displayID, double *coordinates) {
    if (coordinates == NULL) return -1;
    typedef IOReturn (*CopyEDID)(IOAVService, CFDataRef *);
    CopyEDID copyEDID = (CopyEDID)dlsym(RTLD_DEFAULT, "IOAVServiceCopyEDID");
    if (copyEDID == NULL) return -2;
    BRDDCTransport transport = BRCreateTransport(displayID);
    if (transport.service == NULL) return -3;
    CFDataRef data = NULL;
    IOReturn error = copyEDID(transport.service, &data);
    CFRelease(transport.service);
    if (error != KERN_SUCCESS || data == NULL) return -4;
    if (CFDataGetLength(data) < 128) { CFRelease(data); return -5; }
    const uint8_t *e = CFDataGetBytePtr(data);
    const uint8_t header[] = {0,255,255,255,255,255,255,0};
    uint8_t sum = 0;
    for (int i = 0; i < 128; ++i) sum += e[i];
    if (memcmp(e, header, 8) != 0 || sum != 0) { CFRelease(data); return -6; }
    for (int i = 0; i < 8; ++i) {
        int lowByte = i < 4 ? 25 : 26;
        int shift = 6 - 2 * (i % 4);
        coordinates[i] = ((e[27 + i] << 2) | ((e[lowByte] >> shift) & 3)) / 1024.0;
    }
    CFRelease(data);
    return 0;
}

// Sensor event/CCT approach from TrueTone; lifecycle/fallback patterns from
// LuxCurve, LumenShift and mac-utils. Only read APIs are used. See NOTICE.
struct BRAmbientReader {
    CFTypeRef client;
    CFArrayRef list;
    io_service_t root;
    CFIndex preferred;
};

BRAmbientReader *BRCreateAmbientReader(void) {
    BRAmbientReader *r = calloc(1, sizeof(*r));
    if (r) r->root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    return r;
}
void BRReleaseAmbientReader(BRAmbientReader *r) {
    if (!r) return;
    if (r->list) CFRelease(r->list);
    if (r->client) CFRelease(r->client);
    if (r->root) IOObjectRelease(r->root);
    free(r);
}

int32_t BRReadAmbientCached(BRAmbientReader *r, double *lux, double *kelvin, uint8_t *lidClosed) {
    if (!r || lux == NULL || kelvin == NULL || lidClosed == NULL) return -1;
    *lux = NAN; *kelvin = NAN; *lidClosed = 0;
    io_service_t root = r->root;
    if (root != IO_OBJECT_NULL) {
        CFTypeRef closed = IORegistryEntryCreateCFProperty(root,
            CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
        *lidClosed = BRCFBooleanValue(closed) ? 1 : 0;
        if (closed) CFRelease(closed);
    }
    if (*lidClosed) return -2;
    typedef CFTypeRef (*Create)(CFAllocatorRef);
    typedef void (*Match)(CFTypeRef, CFDictionaryRef);
    typedef CFArrayRef (*Services)(CFTypeRef);
    typedef CFTypeRef (*CopyEvent)(CFTypeRef, int32_t, uint32_t, uint64_t);
    typedef double (*FloatValue)(CFTypeRef, uint32_t);
    Create create = (Create)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
    Match match = (Match)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching");
    Services services = (Services)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
    CopyEvent copyEvent = (CopyEvent)dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyEvent");
    FloatValue value = (FloatValue)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    if (!create || !match || !services || !copyEvent || !value) return -3;
    if (!r->client) {
        r->client = create(kCFAllocatorDefault);
        if (!r->client) return -4;
        match(r->client, NULL);
    }
    if (!r->list) r->list = services(r->client);
    CFArrayRef list = r->list;
    int32_t result = -5;
    if (list) {
        const CFIndex count = CFArrayGetCount(list);
        for (CFIndex offset = 0; offset < count; ++offset) {
            const CFIndex i = (r->preferred + offset) % count;
            CFTypeRef event = copyEvent(CFArrayGetValueAtIndex(list, i), 12, 0, 0);
            if (!event) continue;
            double level = value(event, 12 << 16);
            double cct = value(event, (12 << 16) + 0x0a);
            CFRelease(event);
            if (!isfinite(level) || level < 0 || level > 200000) continue;
            *lux = level;
            result = 0;
            if (isfinite(cct) && cct >= 1500 && cct <= 20000) {
                *kelvin = cct;
                r->preferred = i;
                break;
            }
        }
        if (result != 0) { CFRelease(r->list); r->list = NULL; }
    }
    return result;
}
int32_t BRReadAmbientLight(double *lux, double *kelvin, uint8_t *closed) {
    BRAmbientReader *r = BRCreateAmbientReader();
    int32_t result = BRReadAmbientCached(r, lux, kelvin, closed);
    BRReleaseAmbientReader(r);
    return result;
}

static bool BRIsValidVCPReply(const uint8_t *reply, uint8_t code) {
    if (reply[0] != 0x6E || (reply[1] & 0x7F) != 0x08 ||
        reply[2] != 0x02 || reply[3] != 0x00 || reply[4] != code) {
        return false;
    }
    return BRChecksum(0x50, reply, 10) == reply[10];
}

int32_t BRDDCReadVCP(uint32_t displayID,
                     uint8_t code,
                     uint16_t *currentValue,
                     uint16_t *maximumValue) {
    if (currentValue == NULL || maximumValue == NULL) return -1;
    BRDDCTransport transport = BRCreateTransport(displayID);
    if (transport.service == NULL) return -2;

    uint8_t request[4] = {0x82, 0x01, code, 0x00};
    request[3] = BRChecksum(0x6E, request, 3);
    int32_t result = -4;

    for (int retry = 0; retry < 5; retry += 1) {
        bool wrote = false;
        for (int write = 0; write < 2; write += 1) {
            usleep(10000);
            wrote = IOAVServiceWriteI2C(
                transport.service,
                transport.chipAddress,
                kDDCDataAddress,
                request,
                (uint32_t)sizeof(request)
            ) == KERN_SUCCESS;
        }
        if (!wrote) {
            usleep(20000);
            continue;
        }

        usleep(50000);
        uint8_t reply[11] = {0};
        IOReturn readResult = IOAVServiceReadI2C(
            transport.service,
            transport.chipAddress,
            kDDCDataAddress,
            reply,
            (uint32_t)sizeof(reply)
        );
        if (readResult == KERN_SUCCESS && BRIsValidVCPReply(reply, code)) {
            *maximumValue = ((uint16_t)reply[6] << 8) | reply[7];
            *currentValue = ((uint16_t)reply[8] << 8) | reply[9];
            result = 0;
            break;
        }
        result = readResult == KERN_SUCCESS ? -5 : -4;
        usleep(20000);
    }

    CFRelease(transport.service);
    return result;
}

int32_t BRDisplayGetBuiltInBrightness(double *brightness) {
    if (brightness == NULL) return -1;
    uint32_t count = 0;
    CGError listResult = CGGetActiveDisplayList(0, NULL, &count);
    if (listResult != kCGErrorSuccess || count == 0) return -2;

    CGDirectDisplayID displays[count];
    listResult = CGGetActiveDisplayList(count, displays, &count);
    if (listResult != kCGErrorSuccess) return -3;

    for (uint32_t index = 0; index < count; index += 1) {
        if (CGDisplayIsBuiltin(displays[index]) == 0) continue;
        float value = 0.0f;
        int result = DisplayServicesGetBrightness(displays[index], &value);
        if (result == 0 && !isfinite(value)) return -5;
        if (result == 0) {
            if (value < 0.0f) value = 0.0f;
            if (value > 1.0f) value = 1.0f;
            *brightness = value;
            return 0;
        }
        return result;
    }
    return -4;
}

int32_t BRDDCGetExternalDisplayCount(void) {
    return BRDDCCopyExternalDisplays(NULL, 0);
}

int32_t BRDDCWriteBrightnessAll(uint16_t brightness) {
    if (brightness > 100) return -3;
    BRExternalDisplayInfo displays[BR_MAXIMUM_DISPLAYS];
    int32_t count = BRDDCCopyExternalDisplays(displays, BR_MAXIMUM_DISPLAYS);
    if (count <= 0) return count;

    int32_t successes = 0;
    uint32_t boundedCount = (uint32_t)count > BR_MAXIMUM_DISPLAYS
        ? BR_MAXIMUM_DISPLAYS
        : (uint32_t)count;
    for (uint32_t index = 0; index < boundedCount; index += 1) {
        if (BRDDCWriteVCP(displays[index].displayID, kBrightnessVCPCode, brightness) == 0) {
            successes += 1;
        }
    }
    return successes;
}

typedef CGError (*BRGetDisplayListFunction)(
    uint32_t maximumDisplays,
    CGDirectDisplayID *displays,
    uint32_t *displayCount
);
typedef CGError (*BRConfigureDisplayEnabledFunction)(
    CGDisplayConfigRef configuration,
    CGDirectDisplayID displayID,
    bool enabled
);

static void *BRWindowServerHandle(void) {
    static void *handle = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        );
    });
    return handle;
}

static BRGetDisplayListFunction BRGetDisplayListSymbol(void) {
    void *handle = BRWindowServerHandle();
    if (handle == NULL) return NULL;
    void *symbol = dlsym(handle, "CGSGetDisplayList");
    if (symbol == NULL) symbol = dlsym(handle, "SLSGetDisplayList");
    return (BRGetDisplayListFunction)symbol;
}

static BRConfigureDisplayEnabledFunction BRConfigureDisplayEnabledSymbol(void) {
    void *handle = BRWindowServerHandle();
    if (handle == NULL) return NULL;
    void *symbol = dlsym(handle, "CGSConfigureDisplayEnabled");
    if (symbol == NULL) symbol = dlsym(handle, "SLSConfigureDisplayEnabled");
    return (BRConfigureDisplayEnabledFunction)symbol;
}

int32_t BRDisplayConnectionAvailable(void) {
    return BRGetDisplayListSymbol() != NULL && BRConfigureDisplayEnabledSymbol() != NULL;
}

int32_t BRDisplayIsOnline(uint32_t displayID) {
    return CGDisplayIsOnline((CGDirectDisplayID)displayID) != 0 ? 1 : 0;
}

int32_t BRDisplayResolveKnownID(uint32_t previousDisplayID,
                                uint32_t vendorID,
                                uint32_t productID,
                                uint32_t serialNumber,
                                uint32_t *resolvedDisplayID) {
    if (resolvedDisplayID == NULL) return BR_CONNECTION_DISPLAY_NOT_FOUND;
    *resolvedDisplayID = 0;
    BRGetDisplayListFunction getDisplayList = BRGetDisplayListSymbol();
    if (getDisplayList == NULL) return BR_CONNECTION_API_UNAVAILABLE;

    CGDirectDisplayID displayIDs[BR_MAXIMUM_DISPLAYS] = {0};
    uint32_t displayCount = 0;
    CGError listError = getDisplayList(
        BR_MAXIMUM_DISPLAYS,
        displayIDs,
        &displayCount
    );
    if (listError != kCGErrorSuccess) return (int32_t)listError;
    if (displayCount > BR_MAXIMUM_DISPLAYS) displayCount = BR_MAXIMUM_DISPLAYS;

    CGDirectDisplayID onlyMatch = kCGNullDirectDisplay;
    uint32_t matchCount = 0;
    for (uint32_t index = 0; index < displayCount; index += 1) {
        CGDirectDisplayID candidate = displayIDs[index];
        uint32_t candidateVendor = CGDisplayVendorNumber(candidate);
        uint32_t candidateProduct = CGDisplayModelNumber(candidate);
        uint32_t candidateSerial = CGDisplaySerialNumber(candidate);
        if (candidateVendor == 0 && candidateProduct == 0 && candidateSerial == 0) {
            continue;
        }
        if (candidateVendor != vendorID || candidateProduct != productID ||
            candidateSerial != serialNumber) {
            continue;
        }
        onlyMatch = candidate;
        matchCount += 1;
        if (candidate == (CGDirectDisplayID)previousDisplayID) {
            *resolvedDisplayID = candidate;
        }
    }

    if (matchCount == 0) return BR_CONNECTION_DISPLAY_NOT_FOUND;
    if (matchCount == 1) {
        *resolvedDisplayID = onlyMatch;
        return 0;
    }
    return BR_CONNECTION_AMBIGUOUS_DISPLAY;
}

static bool BROtherActiveDisplayExists(CGDirectDisplayID targetDisplayID) {
    uint32_t activeCount = 0;
    if (CGGetActiveDisplayList(0, NULL, &activeCount) != kCGErrorSuccess ||
        activeCount == 0) {
        return false;
    }
    CGDirectDisplayID activeDisplays[BR_MAXIMUM_DISPLAYS] = {0};
    if (activeCount > BR_MAXIMUM_DISPLAYS) activeCount = BR_MAXIMUM_DISPLAYS;
    if (CGGetActiveDisplayList(activeCount, activeDisplays, &activeCount) !=
        kCGErrorSuccess) {
        return false;
    }
    for (uint32_t index = 0; index < activeCount; index += 1) {
        if (activeDisplays[index] != targetDisplayID &&
            CGDisplayIsActive(activeDisplays[index]) != 0) {
            return true;
        }
    }
    return false;
}

int32_t BRDisplaySetEnabled(uint32_t rawDisplayID, uint8_t enabledValue) {
    BRConfigureDisplayEnabledFunction configureEnabled =
        BRConfigureDisplayEnabledSymbol();
    if (configureEnabled == NULL) return BR_CONNECTION_API_UNAVAILABLE;

    CGDirectDisplayID displayID = (CGDirectDisplayID)rawDisplayID;
    bool enabled = enabledValue != 0;
    bool currentlyOnline = CGDisplayIsOnline(displayID) != 0;
    if ((enabled && currentlyOnline) || (!enabled && !currentlyOnline)) return 0;
    if (!enabled && !BROtherActiveDisplayExists(displayID)) {
        return BR_CONNECTION_LAST_ACTIVE;
    }

    CGDisplayConfigRef configuration = NULL;
    CGError beginError = CGBeginDisplayConfiguration(&configuration);
    if (beginError != kCGErrorSuccess || configuration == NULL) {
        return beginError == kCGErrorSuccess
            ? BR_CONNECTION_BEGIN_FAILED
            : (int32_t)beginError;
    }

    if (!enabled && CGDisplayIsInMirrorSet(displayID) != 0) {
        CGError unmirrorError = CGConfigureDisplayMirrorOfDisplay(
            configuration,
            displayID,
            kCGNullDirectDisplay
        );
        if (unmirrorError != kCGErrorSuccess) {
            CGCancelDisplayConfiguration(configuration);
            return (int32_t)unmirrorError;
        }
    }

    CGError configureError = configureEnabled(configuration, displayID, enabled);
    if (configureError != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(configuration);
        return (int32_t)configureError;
    }
    return (int32_t)CGCompleteDisplayConfiguration(
        configuration,
        kCGConfigureForSession
    );
}
