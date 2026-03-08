@import Foundation;
@import IOKit;
#import "DisplayController.h"

@implementation DisplayController {
    DisplayInfos _displays[MAX_DISPLAYS];
    int _displayCount;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _displayCount = 0;
    }
    return self;
}

- (int)displayCount {
    return _displayCount;
}

- (void)refreshDisplayList {
    _displayCount = (int)getOnlineDisplayInfos(_displays);
}

- (DisplayInfos *)displayAtIndex:(int)index {
    if (index < 0 || index >= _displayCount) return NULL;
    return &_displays[index];
}

- (NSString *)displayNameAtIndex:(int)index {
    DisplayInfos *d = [self displayAtIndex:index];
    if (!d) return @"Unknown Display";
    return d->productName ?: @"Unknown Display";
}

- (NSString *)displayLabelAtIndex:(int)index {
    NSString *name = [self displayNameAtIndex:index];
    DisplayInfos *d = [self displayAtIndex:index];
    if (!d) return name;

    // Check if any other display shares the same name
    BOOL hasDuplicate = NO;
    for (int i = 0; i < _displayCount; i++) {
        if (i == index) continue;
        NSString *otherName = _displays[i].productName ?: @"Unknown Display";
        if ([name isEqualToString:otherName]) {
            hasDuplicate = YES;
            break;
        }
    }

    if (!hasDuplicate) return name;

    // Disambiguate: prefer alphanumeric serial, fall back to numeric serial, then index
    if (d->alphNumSerial.length > 0) {
        return [NSString stringWithFormat:@"%@ (%@)", name, d->alphNumSerial];
    }
    if (d->serial != 0) {
        return [NSString stringWithFormat:@"%@ (S/N %u)", name, d->serial];
    }
    return [NSString stringWithFormat:@"%@ (#%d)", name, index + 1];
}

- (NSString *)displayUUIDAtIndex:(int)index {
    DisplayInfos *d = [self displayAtIndex:index];
    if (!d) return @"";
    return d->uuid ?: @"";
}

- (int)displayIndexForUUID:(NSString *)uuid {
    for (int i = 0; i < _displayCount; i++) {
        if ([_displays[i].uuid isEqualToString:uuid]) {
            return i;
        }
    }
    return -1;
}

#pragma mark - DDC Operations

- (IOAVServiceRef)avServiceForDisplayIndex:(int)index {
    DisplayInfos *d = [self displayAtIndex:index];
    if (!d) return NULL;
    IOAVServiceRef service = getDisplayAVService(d);
    if (!service && index == 0) {
        service = getDefaultDisplayAVService();
    }
    return service;
}

- (DDCValue)readAttribute:(UInt8)attrCode forDisplayIndex:(int)index {
    DDCValue fail = {-1, -1};

    IOAVServiceRef avService = [self avServiceForDisplayIndex:index];
    if (!avService) return fail;

    DDCPacket packet = createDDCPacket(attrCode);
    prepareDDCRead(packet.data);

    IOReturn err = performDDCWrite(avService, &packet);
    if (err) return fail;

    DDCPacket readPacket = {};
    readPacket.inputAddr = packet.inputAddr;
    err = performDDCRead(avService, &readPacket);
    if (err) return fail;

    return convertI2CtoDDC((char *)readPacket.data);
}

- (BOOL)writeAttribute:(UInt8)attrCode value:(UInt16)value forDisplayIndex:(int)index {
    IOAVServiceRef avService = [self avServiceForDisplayIndex:index];
    if (!avService) return NO;

    DDCPacket packet = createDDCPacket(attrCode);
    prepareDDCWrite(packet.data, (UInt8)value);

    IOReturn err = performDDCWrite(avService, &packet);
    return err == kIOReturnSuccess;
}

- (NSArray<NSNumber *> *)probeAttributesForDisplayIndex:(int)index {
    NSMutableArray *supported = [NSMutableArray array];
    NSArray *allCodes = [DisplayController allAttributeCodes];

    for (NSNumber *code in allCodes) {
        UInt8 attrCode = [code unsignedCharValue];
        DDCValue val = [self readAttribute:attrCode forDisplayIndex:index];
        if (val.curValue != -1) {
            [supported addObject:code];
        }
    }
    return [supported copy];
}

#pragma mark - Attribute Metadata

+ (NSString *)nameForAttribute:(UInt8)attrCode {
    switch (attrCode) {
        case LUMINANCE:  return @"Brightness";
        case CONTRAST:   return @"Contrast";
        case VOLUME:     return @"Volume";
        case MUTE:       return @"Mute";
        case INPUT:      return @"Input Source";
        case INPUT_ALT:  return @"Input Source (LG)";
        case STANDBY:    return @"Standby";
        case RED:        return @"Red";
        case GREEN:      return @"Green";
        case BLUE:       return @"Blue";
        case PBP_INPUT:  return @"PBP Input";
        case PBP:        return @"PBP Mode";
        case KVM:        return @"KVM";
        default:         return @"Unknown";
    }
}

+ (NSArray<NSNumber *> *)allAttributeCodes {
    return @[
        @(LUMINANCE), @(CONTRAST), @(VOLUME), @(MUTE),
        @(INPUT), @(INPUT_ALT), @(STANDBY),
        @(RED), @(GREEN), @(BLUE),
        @(PBP_INPUT), @(PBP), @(KVM)
    ];
}

+ (NSArray<NSNumber *> *)sliderAttributeCodes {
    return @[@(LUMINANCE), @(CONTRAST), @(VOLUME), @(RED), @(GREEN), @(BLUE)];
}

+ (NSArray<NSNumber *> *)toggleAttributeCodes {
    return @[@(MUTE)];
}

+ (NSArray<NSNumber *> *)popupAttributeCodes {
    return @[@(INPUT), @(INPUT_ALT), @(PBP), @(PBP_INPUT), @(KVM)];
}

+ (NSArray<NSNumber *> *)buttonAttributeCodes {
    return @[@(STANDBY)];
}

@end
