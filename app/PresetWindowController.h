@import AppKit;
#import "DisplayController.h"
#import "PresetManager.h"

@interface PresetWindowController : NSWindowController

- (instancetype)initWithPresetManager:(PresetManager*)presetManager
                    displayController:(DisplayController*)displayController;

@end
