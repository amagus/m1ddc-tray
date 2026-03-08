@import AppKit;
#import "DisplayController.h"

@interface ControlWindowController : NSWindowController

- (instancetype)initWithDisplayIndex:(int)index
                   displayController:(DisplayController *)controller;

@end
