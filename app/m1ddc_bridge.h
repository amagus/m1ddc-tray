#ifndef M1DDC_BRIDGE_H
#define M1DDC_BRIDGE_H

// Bridge header for including m1ddc C/ObjC library from Objective-C++.
// The library headers use @import which conflicts with extern "C",
// so we pre-import the frameworks and redefine the necessary types
// and function declarations with proper C linkage.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

// From ioregistry.h
#ifndef MAX_DISPLAYS
#define MAX_DISPLAYS 4
#endif
#define UUID_SIZE 37

typedef CFTypeRef IOAVServiceRef;

typedef struct {
  CGDirectDisplayID id;
  io_service_t adapter;
  NSString* ioLocation;
  NSString* uuid;
  NSString* edid;
  NSString* productName;
  NSString* manufacturer;
  NSString* alphNumSerial;
  UInt32 serial;
  UInt32 model;
  UInt32 vendor;
} DisplayInfos;

// From i2c.h
#define DEFAULT_INPUT_ADDRESS 0x51
#define ALTERNATE_INPUT_ADDRESS 0x50

#define LUMINANCE 0x10
#define CONTRAST 0x12
#define VOLUME 0x62
#define MUTE 0x8D
#define INPUT 0x60
#define INPUT_ALT 0xF4
#define STANDBY 0xD6
#define RED 0x16
#define GREEN 0x18
#define BLUE 0x1A
#define PBP_INPUT 0xE8
#define PBP 0xE9
#define KVM 0xE7

#define DDC_WAIT 10000
#define DDC_ITERATIONS 2
#define DDC_BUFFER_SIZE 256

typedef struct {
  UInt8 data[DDC_BUFFER_SIZE];
  UInt8 inputAddr;
} DDCPacket;

typedef struct {
  signed char curValue;
  signed char maxValue;
} DDCValue;

#ifdef __cplusplus
extern "C" {
#endif

// ioregistry functions
CGDisplayCount getOnlineDisplayInfos(DisplayInfos* displayInfos);
DisplayInfos* selectDisplay(DisplayInfos* displays, int connectedDisplays,
                            char* displayIdentifier);
IOAVServiceRef getDefaultDisplayAVService(void);
IOAVServiceRef getDisplayAVService(DisplayInfos* displayInfos);

// i2c functions
DDCPacket createDDCPacket(UInt8 attrCode);
void prepareDDCRead(UInt8* data);
void prepareDDCWrite(UInt8* data, UInt8 setValue);
IOReturn performDDCWrite(IOAVServiceRef avService, DDCPacket* packet);
IOReturn performDDCRead(IOAVServiceRef avService, DDCPacket* packet);
DDCValue convertI2CtoDDC(char* i2cBytes);
IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                            uint32_t offset, void* outputBuffer,
                            uint32_t outputBufferSize);
IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                             uint32_t dataAddress, void* inputBuffer,
                             uint32_t inputBufferSize);

#ifdef __cplusplus
}
#endif

#endif
