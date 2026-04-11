@import Foundation;
#import "DisplayController.h"

@interface PresetAction : NSObject
@property(nonatomic, copy) NSString* displayUUID;
@property(nonatomic, assign) UInt8 attributeCode;
@property(nonatomic, assign) UInt16 value;

- (NSDictionary*)toDictionary;
+ (PresetAction*)fromDictionary:(NSDictionary*)dict;
@end

@interface Preset : NSObject
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, strong) NSMutableArray<PresetAction*>* actions;

- (NSDictionary*)toDictionary;
+ (Preset*)fromDictionary:(NSDictionary*)dict;
@end

@interface PresetManager : NSObject

- (NSArray<Preset*>*)allPresets;
- (void)savePreset:(Preset*)preset;
- (void)deletePreset:(NSString*)identifier;
- (void)applyPreset:(Preset*)preset
    withDisplayController:(DisplayController*)controller
               completion:(void (^)(BOOL success))completion;

@end
