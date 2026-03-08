@import Foundation;
#import "m1ddc_bridge.h"

@interface DisplayController : NSObject

@property (nonatomic, readonly) int displayCount;

- (void)refreshDisplayList;
- (DisplayInfos *)displayAtIndex:(int)index;
- (NSString *)displayNameAtIndex:(int)index;
- (NSString *)displayLabelAtIndex:(int)index;
- (NSString *)displayUUIDAtIndex:(int)index;
- (int)displayIndexForUUID:(NSString *)uuid;

// DDC operations (synchronous - call from background queue)
- (DDCValue)readAttribute:(UInt8)attrCode forDisplayIndex:(int)index;
- (BOOL)writeAttribute:(UInt8)attrCode value:(UInt16)value forDisplayIndex:(int)index;

// Probe which attributes a display supports (synchronous - call from background queue)
- (NSArray<NSNumber *> *)probeAttributesForDisplayIndex:(int)index;

// Attribute metadata
+ (NSString *)nameForAttribute:(UInt8)attrCode;
+ (NSArray<NSNumber *> *)allAttributeCodes;
+ (NSArray<NSNumber *> *)sliderAttributeCodes;
+ (NSArray<NSNumber *> *)toggleAttributeCodes;
+ (NSArray<NSNumber *> *)popupAttributeCodes;
+ (NSArray<NSNumber *> *)buttonAttributeCodes;

@end
