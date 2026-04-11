@import Foundation;
@import IOKit;
#import "DisplayController.h"

@implementation DisplayController {
  DisplayInfos _displays[MAX_DISPLAYS];
  int _displayCount;
  NSMutableDictionary<NSString*, NSArray<NSDictionary*>*>* _inputOptionsByUUID;
}

// Known DDC/CI input source value → label mapping
static NSDictionary<NSNumber*, NSString*>* const kInputSourceLabels = @{
  @(0x01) : @"VGA 1",
  @(0x02) : @"VGA 2",
  @(0x03) : @"DVI 1",
  @(0x04) : @"DVI 2",
  @(0x0F) : @"DisplayPort 1",
  @(0x10) : @"DisplayPort 2",
  @(0x11) : @"HDMI 1",
  @(0x12) : @"HDMI 2",
  @(0x13) : @"HDMI 3",
  @(0x14) : @"HDMI 4",
  @(0x1B) : @"USB-C",
  @(0x1C) : @"USB-C 2",
  @(0x90) : @"DisplayPort 3",
  @(0x91) : @"DisplayPort 4",
};

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _displayCount = 0;
    _inputOptionsByUUID = [NSMutableDictionary dictionary];
  }
  return self;
}

- (int)displayCount {
  return _displayCount;
}

- (void)refreshDisplayList {
  int newCount = (int)getOnlineDisplayInfos(_displays);

  // Evict cached options for displays that are no longer connected
  NSMutableSet<NSString*>* currentUUIDs = [NSMutableSet set];
  for (int i = 0; i < newCount; i++) {
    if (_displays[i].uuid != nil)
      [currentUUIDs addObject:_displays[i].uuid];
  }
  for (NSString* uuid in [_inputOptionsByUUID allKeys]) {
    if (![currentUUIDs containsObject:uuid])
      [_inputOptionsByUUID removeObjectForKey:uuid];
  }

  _displayCount = newCount;
}

// Read the DDC/CI capabilities string in chunks (opcode 0xF3 / reply 0xE3).
// Synchronous — call from a background queue.
- (NSString*)readCapabilitiesStringForService:(IOAVServiceRef)avService {
  NSMutableString* result = [NSMutableString string];
  UInt16 offset = 0;

  for (int attempt = 0; attempt < 100; attempt++) {
    UInt8 req[8] = {0};
    req[0] = 0x83; // length byte: 0x80 | 3 data bytes
    req[1] = 0xF3; // Capabilities Request opcode
    req[2] = (offset >> 8) & 0xFF;
    req[3] = offset & 0xFF;
    req[4] = 0x6E ^ req[0] ^ req[1] ^ req[2] ^ req[3]; // checksum

    usleep(DDC_WAIT);
    if (IOAVServiceWriteI2C(avService, 0x37, 0x51, req, 5))
      break;

    UInt8 resp[64] = {0};
    usleep(DDC_WAIT);
    if (IOAVServiceReadI2C(avService, 0x37, 0x51, resp, sizeof(resp)))
      break;

    // Response: [?][len|0x80][0xE3][off_hi][off_lo][data…][checksum]
    if (resp[2] != 0xE3)
      break;

    int dataLen =
        (resp[1] & 0x7F) - 4; // subtract opcode + offset(2) + checksum
    if (dataLen <= 0)
      break;

    BOOL done = NO;
    for (int j = 0; j < dataLen; j++) {
      char c = (char)resp[5 + j];
      if (c == 0) {
        done = YES;
        break;
      }
      [result appendFormat:@"%c", c];
    }
    if (done)
      break;
    offset += dataLen;
  }

  return result.length > 0 ? result : nil;
}

// Parse "60(01 0F 11 12 1B)" from the capabilities string and return labelled
// options.
- (NSArray<NSDictionary*>*)parseInputOptionsFromCapabilities:(NSString*)caps {
  NSRegularExpression* rx = [NSRegularExpression
      regularExpressionWithPattern:@"\\b60\\(([^)]+)\\)"
                           options:NSRegularExpressionCaseInsensitive
                             error:nil];
  NSTextCheckingResult* match =
      [rx firstMatchInString:caps options:0 range:NSMakeRange(0, caps.length)];
  if (match == nil)
    return nil;

  NSString* valuesStr = [caps substringWithRange:[match rangeAtIndex:1]];
  NSDictionary* labels = kInputSourceLabels;
  NSMutableArray<NSDictionary*>* options = [NSMutableArray array];

  for (NSString* token in [valuesStr
           componentsSeparatedByCharactersInSet:[NSCharacterSet
                                                    whitespaceCharacterSet]]) {
    NSString* hex = [token
        stringByTrimmingCharactersInSet:[NSCharacterSet
                                            whitespaceAndNewlineCharacterSet]];
    if (!hex.length)
      continue;
    unsigned int val;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&val])
      continue;
    NSString* label =
        labels[@(val)] != nil ? labels[@(val)]
                              : [NSString stringWithFormat:@"Source 0x%02X", val];
    [options addObject:@{@"label" : label, @"value" : @(val)}];
  }
  return options.count > 0 ? options : nil;
}

// Load capabilities for any display not yet cached. Synchronous — call from
// background queue. Returns YES if new data was loaded.
- (BOOL)loadCapabilitiesIfNeeded {
  BOOL loaded = NO;
  for (int i = 0; i < _displayCount; i++) {
    NSString* uuid = [self displayUUIDAtIndex:i];
    if (uuid.length == 0 || _inputOptionsByUUID[uuid] != nil)
      continue;

    IOAVServiceRef svc = [self avServiceForDisplayIndex:i];
    NSArray* options = nil;
    if (svc != NULL) {
      NSString* caps = [self readCapabilitiesStringForService:svc];
      if (caps != nil)
        options = [self parseInputOptionsFromCapabilities:caps];
    }
    // Store result — empty array means "tried but found nothing", triggers
    // fallback
    _inputOptionsByUUID[uuid] = options != nil ? options : @[];
    loaded = YES;
  }
  return loaded;
}

// Returns labelled input options for a display. Uses capabilities cache when
// available, falls back to hardcoded standard/LG lists.
- (NSArray<NSDictionary*>*)inputOptionsForDisplayIndex:(int)index {
  NSString* uuid = [self displayUUIDAtIndex:index];
  NSArray<NSDictionary*>* cached = _inputOptionsByUUID[uuid];
  if (cached.count > 0)
    return cached;

  // Fallback hardcoded lists
  if ([self usesAlternateInputForIndex:index]) {
    return @[
      @{@"label" : @"DisplayPort 1", @"value" : @(208)},
      @{@"label" : @"DisplayPort 2", @"value" : @(209)},
      @{@"label" : @"HDMI 1", @"value" : @(144)},
      @{@"label" : @"HDMI 2", @"value" : @(145)},
      @{@"label" : @"USB-C / DP 3", @"value" : @(210)},
    ];
  }
  return @[
    @{@"label" : @"DisplayPort 1", @"value" : @(15)},
    @{@"label" : @"DisplayPort 2", @"value" : @(16)},
    @{@"label" : @"HDMI 1", @"value" : @(17)},
    @{@"label" : @"HDMI 2", @"value" : @(18)},
    @{@"label" : @"USB-C", @"value" : @(27)},
  ];
}

- (DisplayInfos*)displayAtIndex:(int)index {
  if (index < 0 || index >= _displayCount)
    return NULL;
  return &_displays[index];
}

- (NSString*)displayNameAtIndex:(int)index {
  DisplayInfos* d = [self displayAtIndex:index];
  if (d == NULL)
    return @"Unknown Display";
  return d->productName != nil ? d->productName : @"Unknown Display";
}

- (NSString*)displayLabelAtIndex:(int)index {
  // Check for custom name first
  NSString* uuid = [self displayUUIDAtIndex:index];
  NSString* custom = [self customNameForUUID:uuid];
  if (custom.length > 0)
    return custom;

  NSString* name = [self displayNameAtIndex:index];
  DisplayInfos* d = [self displayAtIndex:index];
  if (d == NULL)
    return name;

  // Check if any other display shares the same name
  BOOL hasDuplicate = NO;
  for (int i = 0; i < _displayCount; i++) {
    if (i == index)
      continue;
    NSString* otherName = _displays[i].productName != nil
                              ? _displays[i].productName
                              : @"Unknown Display";
    if ([name isEqualToString:otherName]) {
      hasDuplicate = YES;
      break;
    }
  }

  if (!hasDuplicate)
    return name;

  // Disambiguate: prefer alphanumeric serial, fall back to numeric serial, then
  // index
  if (d->alphNumSerial.length > 0) {
    return [NSString stringWithFormat:@"%@ (%@)", name, d->alphNumSerial];
  }
  if (d->serial != 0) {
    return [NSString stringWithFormat:@"%@ (S/N %u)", name, d->serial];
  }
  return [NSString stringWithFormat:@"%@ (#%d)", name, index + 1];
}

- (NSString*)displayUUIDAtIndex:(int)index {
  DisplayInfos* d = [self displayAtIndex:index];
  if (d == NULL)
    return @"";
  return d->uuid != nil ? d->uuid : @"";
}

- (int)displayIndexForUUID:(NSString*)uuid {
  for (int i = 0; i < _displayCount; i++) {
    if ([_displays[i].uuid isEqualToString:uuid]) {
      return i;
    }
  }
  return -1;
}

#pragma mark - Per-Display Persistent Settings

static NSString* const kDisplaySettingsKey = @"DisplaySettings";

- (NSMutableDictionary*)settingsForUUID:(NSString*)uuid {
  NSDictionary* all = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kDisplaySettingsKey];
  NSDictionary* s = all[uuid];
  return s != nil ? [s mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveSettings:(NSDictionary*)settings forUUID:(NSString*)uuid {
  NSDictionary* existing = [[NSUserDefaults standardUserDefaults]
      dictionaryForKey:kDisplaySettingsKey];
  NSMutableDictionary* all = [(existing != nil ? existing : @{}) mutableCopy];
  all[uuid] = settings;
  [[NSUserDefaults standardUserDefaults] setObject:all
                                            forKey:kDisplaySettingsKey];
}

- (NSString*)customNameForUUID:(NSString*)uuid {
  if (!uuid.length)
    return nil;
  return [self settingsForUUID:uuid][@"customName"];
}

- (void)setCustomName:(NSString*)name forUUID:(NSString*)uuid {
  if (!uuid.length)
    return;
  NSMutableDictionary* s = [self settingsForUUID:uuid];
  if (name.length > 0) {
    s[@"customName"] = name;
  } else {
    [s removeObjectForKey:@"customName"];
  }
  [self saveSettings:s forUUID:uuid];
}

- (NSString*)inputProfileForUUID:(NSString*)uuid {
  if (!uuid.length)
    return @"auto";
  NSString* profile = [self settingsForUUID:uuid][@"inputProfile"];
  return profile != nil ? profile : @"auto";
}

- (void)setInputProfile:(NSString*)profile forUUID:(NSString*)uuid {
  if (!uuid.length)
    return;
  NSMutableDictionary* s = [self settingsForUUID:uuid];
  if ([profile isEqualToString:@"auto"]) {
    [s removeObjectForKey:@"inputProfile"];
  } else {
    s[@"inputProfile"] = profile;
  }
  [self saveSettings:s forUUID:uuid];
}

- (NSString*)manufacturerForIndex:(int)index {
  DisplayInfos* d = [self displayAtIndex:index];
  if (d == NULL)
    return @"";
  return d->manufacturer != nil ? d->manufacturer : @"";
}

- (BOOL)usesAlternateInputForIndex:(int)index {
  NSString* uuid = [self displayUUIDAtIndex:index];
  NSString* profile = [self inputProfileForUUID:uuid];

  if ([profile isEqualToString:@"lg"])
    return YES;
  if ([profile isEqualToString:@"standard"])
    return NO;

  // Auto-detect: LG uses manufacturer ID "GSM" (GoldStar Manufacturing)
  NSString* mfr = [self manufacturerForIndex:index];
  return [mfr isEqualToString:@"GSM"] ||
         [mfr localizedCaseInsensitiveContainsString:@"LG"];
}

#pragma mark - DDC Operations

- (IOAVServiceRef)avServiceForDisplayIndex:(int)index {
  DisplayInfos* d = [self displayAtIndex:index];
  if (d == NULL)
    return NULL;
  IOAVServiceRef service = getDisplayAVService(d);
  if (service == NULL && index == 0) {
    service = getDefaultDisplayAVService();
  }
  return service;
}

- (DDCValue)readAttribute:(UInt8)attrCode forDisplayIndex:(int)index {
  DDCValue fail = {-1, -1};

  IOAVServiceRef avService = [self avServiceForDisplayIndex:index];
  if (avService == NULL)
    return fail;

  DDCPacket packet = createDDCPacket(attrCode);
  prepareDDCRead(packet.data);

  IOReturn err = performDDCWrite(avService, &packet);
  if (err)
    return fail;

  DDCPacket readPacket = {};
  readPacket.inputAddr = packet.inputAddr;
  err = performDDCRead(avService, &readPacket);
  if (err)
    return fail;

  return convertI2CtoDDC((char*)readPacket.data);
}

- (BOOL)writeAttribute:(UInt8)attrCode
                 value:(UInt16)value
       forDisplayIndex:(int)index {
  IOAVServiceRef avService = [self avServiceForDisplayIndex:index];
  if (avService == NULL)
    return NO;

  DDCPacket packet = createDDCPacket(attrCode);
  prepareDDCWrite(packet.data, (UInt8)value);

  IOReturn err = performDDCWrite(avService, &packet);
  return err == kIOReturnSuccess;
}

- (NSArray<NSNumber*>*)probeAttributesForDisplayIndex:(int)index {
  NSMutableArray* supported = [NSMutableArray array];
  NSArray* allCodes = [DisplayController allAttributeCodes];

  for (NSNumber* code in allCodes) {
    UInt8 attrCode = [code unsignedCharValue];
    DDCValue val = [self readAttribute:attrCode forDisplayIndex:index];
    if (val.curValue != -1) {
      [supported addObject:code];
    }
  }
  return [supported copy];
}

#pragma mark - Attribute Metadata

+ (NSString*)nameForAttribute:(UInt8)attrCode {
  switch (attrCode) {
  case LUMINANCE:
    return @"Brightness";
  case CONTRAST:
    return @"Contrast";
  case VOLUME:
    return @"Volume";
  case MUTE:
    return @"Mute";
  case INPUT:
    return @"Input Source";
  case INPUT_ALT:
    return @"Input Source";
  case STANDBY:
    return @"Standby";
  case RED:
    return @"Red";
  case GREEN:
    return @"Green";
  case BLUE:
    return @"Blue";
  case PBP_INPUT:
    return @"PBP Input";
  case PBP:
    return @"PBP Mode";
  case KVM:
    return @"KVM";
  default:
    return @"Unknown";
  }
}

- (UInt8)inputAttributeCodeForIndex:(int)index {
  return [self usesAlternateInputForIndex:index] ? INPUT_ALT : INPUT;
}

+ (NSArray<NSNumber*>*)allAttributeCodes {
  return @[
    @(LUMINANCE), @(CONTRAST), @(VOLUME), @(MUTE), @(INPUT), @(STANDBY), @(RED),
    @(GREEN), @(BLUE), @(PBP_INPUT), @(PBP), @(KVM)
  ];
}

+ (NSArray<NSNumber*>*)sliderAttributeCodes {
  return @[ @(LUMINANCE), @(CONTRAST), @(VOLUME), @(RED), @(GREEN), @(BLUE) ];
}

+ (NSArray<NSNumber*>*)toggleAttributeCodes {
  return @[ @(MUTE) ];
}

+ (NSArray<NSNumber*>*)popupAttributeCodes {
  return @[ @(INPUT), @(PBP), @(PBP_INPUT), @(KVM) ];
}

+ (NSArray<NSNumber*>*)buttonAttributeCodes {
  return @[ @(STANDBY) ];
}

@end
