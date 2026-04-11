@import Foundation;
#import "PresetManager.h"

static NSString* const kPresetsKey = @"presets";

#pragma mark - PresetAction

@implementation PresetAction

- (NSDictionary*)toDictionary {
  return @{
    @"displayUUID" : self.displayUUID ?: @"",
    @"attributeCode" : @(self.attributeCode),
    @"value" : @(self.value),
  };
}

+ (PresetAction*)fromDictionary:(NSDictionary*)dict {
  PresetAction* action = [[PresetAction alloc] init];
  action.displayUUID = dict[@"displayUUID"] ?: @"";
  action.attributeCode = (UInt8)[dict[@"attributeCode"] unsignedIntValue];
  action.value = (UInt16)[dict[@"value"] unsignedIntValue];
  return action;
}

@end

#pragma mark - Preset

@implementation Preset

- (instancetype)init {
  self = [super init];
  if (self) {
    _identifier = [[NSUUID UUID] UUIDString];
    _actions = [NSMutableArray array];
  }
  return self;
}

- (NSDictionary*)toDictionary {
  NSMutableArray* actionDicts = [NSMutableArray array];
  for (PresetAction* action in self.actions) {
    [actionDicts addObject:[action toDictionary]];
  }
  return @{
    @"name" : self.name ?: @"",
    @"identifier" : self.identifier ?: @"",
    @"actions" : actionDicts,
  };
}

+ (Preset*)fromDictionary:(NSDictionary*)dict {
  Preset* preset = [[Preset alloc] init];
  preset.name = dict[@"name"] ?: @"Untitled";
  preset.identifier = dict[@"identifier"] ?: [[NSUUID UUID] UUIDString];
  preset.actions = [NSMutableArray array];
  for (NSDictionary* actionDict in dict[@"actions"]) {
    [preset.actions addObject:[PresetAction fromDictionary:actionDict]];
  }
  return preset;
}

@end

#pragma mark - PresetManager

@implementation PresetManager

- (NSArray<Preset*>*)allPresets {
  NSArray* dicts =
      [[NSUserDefaults standardUserDefaults] arrayForKey:kPresetsKey];
  if (!dicts)
    return @[];

  NSMutableArray<Preset*>* presets = [NSMutableArray array];
  for (NSDictionary* dict in dicts) {
    [presets addObject:[Preset fromDictionary:dict]];
  }
  return presets;
}

- (void)persistPresets:(NSArray<Preset*>*)presets {
  NSMutableArray* dicts = [NSMutableArray array];
  for (Preset* preset in presets) {
    [dicts addObject:[preset toDictionary]];
  }
  [[NSUserDefaults standardUserDefaults] setObject:dicts forKey:kPresetsKey];
}

- (void)savePreset:(Preset*)preset {
  NSMutableArray<Preset*>* presets = [[self allPresets] mutableCopy];

  // Replace existing or append
  NSInteger existingIndex = -1;
  for (NSInteger i = 0; i < (NSInteger)presets.count; i++) {
    if ([presets[i].identifier isEqualToString:preset.identifier]) {
      existingIndex = i;
      break;
    }
  }

  if (existingIndex >= 0) {
    presets[existingIndex] = preset;
  } else {
    [presets addObject:preset];
  }

  [self persistPresets:presets];
}

- (void)deletePreset:(NSString*)identifier {
  NSMutableArray<Preset*>* presets = [[self allPresets] mutableCopy];
  [presets
      filterUsingPredicate:[NSPredicate predicateWithFormat:@"identifier != %@",
                                                            identifier]];
  [self persistPresets:presets];
}

- (void)applyPreset:(Preset*)preset
    withDisplayController:(DisplayController*)controller
               completion:(void (^)(BOOL success))completion {
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL allSuccess = YES;
        for (PresetAction* action in preset.actions) {
          int displayIndex =
              [controller displayIndexForUUID:action.displayUUID];
          if (displayIndex < 0) {
            allSuccess = NO;
            continue;
          }
          UInt8 ddcCode = action.attributeCode;
          if (ddcCode == INPUT) {
            ddcCode = [controller inputAttributeCodeForIndex:displayIndex];
          }
          BOOL ok = [controller writeAttribute:ddcCode
                                         value:action.value
                               forDisplayIndex:displayIndex];
          if (!ok)
            allSuccess = NO;
        }
        if (completion) {
          dispatch_async(dispatch_get_main_queue(), ^{
            completion(allSuccess);
          });
        }
      });
}

@end
