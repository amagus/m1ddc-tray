@import AppKit;
#import "PresetManager.h"
#import "DisplayController.h"

@interface PresetWindowController : NSWindowController

- (instancetype)initWithPresetManager:(PresetManager *)presetManager
                    displayController:(DisplayController *)displayController;

@end
