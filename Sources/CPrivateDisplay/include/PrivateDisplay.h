#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 0 and writes a normalized 0...1 value when a built-in display exists.
int32_t BRDisplayGetBuiltInBrightness(double *brightness);
/// Read-only ambient sensor sample. -1 means unavailable; no readings invented.
int32_t BRReadAmbientLight(double *lux, double *kelvin, uint8_t *lidClosed);
typedef struct BRAmbientReader BRAmbientReader;
BRAmbientReader *BRCreateAmbientReader(void);
void BRReleaseAmbientReader(BRAmbientReader *reader);
int32_t BRReadAmbientCached(BRAmbientReader *reader, double *lux, double *kelvin, uint8_t *closed);
int32_t BRWatchBrightness(void (*callback)(void));
void BRUnwatchBrightness(void);
/// EDID chromaticities in rx,ry,gx,gy,bx,by,wx,wy order, resolved per display.
int32_t BRDisplayGetChromaticities(uint32_t displayID, double *coordinates);

/// Returns the number of external Apple Silicon display services that can carry DDC.
int32_t BRDDCGetExternalDisplayCount(void);

#define BR_DISPLAY_NAME_LENGTH 128
#define BR_DISPLAY_IDENTITY_LENGTH 128
#define BR_DISPLAY_LOCATION_LENGTH 1024

/// A stable display identity plus the current CoreGraphics routing information.
/// The CoreGraphics display ID is transient; stableID is derived from the EDID UUID.
typedef struct {
    uint32_t displayID;
    uint32_t vendorID;
    uint32_t productID;
    uint32_t serialNumber;
    uint8_t isMain;
    uint8_t supportsStandby;
    char name[BR_DISPLAY_NAME_LENGTH];
    char stableID[BR_DISPLAY_IDENTITY_LENGTH];
    char edidUUID[BR_DISPLAY_IDENTITY_LENGTH];
    char ioLocation[BR_DISPLAY_LOCATION_LENGTH];
} BRExternalDisplayInfo;

/// Copies online external displays into `displays` and returns the total count.
/// Pass NULL/0 to query the required capacity.
int32_t BRDDCCopyExternalDisplays(BRExternalDisplayInfo *displays, uint32_t capacity);

/// Reads one MCCS VCP feature from one CoreGraphics display.
/// Returns 0 only for a checksum-valid reply from the monitor.
int32_t BRDDCReadVCP(uint32_t displayID,
                     uint8_t code,
                     uint16_t *currentValue,
                     uint16_t *maximumValue);

/// Writes one MCCS VCP feature to one CoreGraphics display.
/// Returns 0 when macOS accepted the per-display I2C transaction.
int32_t BRDDCWriteVCP(uint32_t displayID, uint8_t code, uint16_t value);

/// Writes MCCS brightness (VCP 0x10) to every external display service.
/// Returns the number of services that accepted the write, or a negative error code.
int32_t BRDDCWriteBrightnessAll(uint16_t brightness);

/// Returns 1 when the private, session-scoped display connection APIs are
/// available on this macOS version, otherwise 0.
int32_t BRDisplayConnectionAvailable(void);

/// Resolves a display from the WindowServer list, which includes displays that
/// were logically disconnected and are absent from the public online list.
/// Returns 0 on success and writes the current CoreGraphics display ID.
int32_t BRDisplayResolveKnownID(uint32_t previousDisplayID,
                                uint32_t vendorID,
                                uint32_t productID,
                                uint32_t serialNumber,
                                uint32_t *resolvedDisplayID);

/// Connects or disconnects one display for the current login session. A
/// disconnect is refused if it would leave no other active display.
int32_t BRDisplaySetEnabled(uint32_t displayID, uint8_t enabled);

/// Returns 1 if the display is in the public online display list, otherwise 0.
int32_t BRDisplayIsOnline(uint32_t displayID);

#ifdef __cplusplus
}
#endif
