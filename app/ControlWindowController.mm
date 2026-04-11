@import AppKit;
#import "ControlWindowController.h"

// Input source options for NSPopUpButton
typedef struct {
  const char* label;
  UInt16 value;
} PopupOption;

static const PopupOption kPBPOptions[] = {
    {"Off", 0},          {"Small Window", 33}, {"Large Window", 34},
    {"50/50 Split", 36}, {"26/74 Split", 43},  {"74/26 Split", 44},
    {"2x2", 65},
};

static const PopupOption kPBPInputOptions[] = {
    {"DisplayPort 1", 15},
    {"DisplayPort 2", 16},
    {"HDMI 1", 17},
    {"HDMI 2", 18},
};

static const PopupOption kKVMOptions[] = {
    {"USB 1-2-3-4", 1728},
    {"Next Device", 65280},
};

@interface ControlWindowController () <NSTextFieldDelegate>
@property(nonatomic, assign) int displayIndex;
@property(nonatomic, strong) DisplayController* displayController;
@property(nonatomic, strong) NSStackView* mainStack;
@property(nonatomic, strong) NSProgressIndicator* spinner;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSSlider*>* sliders;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, NSTextField*>* valueLabels;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSButton*>* toggles;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, NSPopUpButton*>* popups;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, NSView*>* controlRows;
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber*, NSTimer*>* debounceTimers;
@property(nonatomic, strong) dispatch_queue_t ddcQueue;
@property(nonatomic, strong) NSTextField* nameField;
@property(nonatomic, strong) NSPopUpButton* profilePopup;
@end

@implementation ControlWindowController

- (instancetype)initWithDisplayIndex:(int)index
                   displayController:(DisplayController*)controller {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 380, 250)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                  backing:NSBackingStoreBuffered
                    defer:NO];

  window.title = [controller displayLabelAtIndex:index];
  window.releasedWhenClosed = NO;
  [window center];

  self = [super initWithWindow:window];
  if (self != nullptr) {
    _displayIndex = index;
    _displayController = controller;
    _sliders = [NSMutableDictionary dictionary];
    _valueLabels = [NSMutableDictionary dictionary];
    _toggles = [NSMutableDictionary dictionary];
    _popups = [NSMutableDictionary dictionary];
    _controlRows = [NSMutableDictionary dictionary];
    _debounceTimers = [NSMutableDictionary dictionary];
    _ddcQueue = dispatch_queue_create("com.amagus.m1ddc-tray.ddc",
                                      DISPATCH_QUEUE_SERIAL);
    [self buildUI];
    [self probeAndRefresh];
  }
  return self;
}

#pragma mark - UI Construction

- (void)buildUI {
  _mainStack = [[NSStackView alloc] init];
  _mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
  _mainStack.alignment = NSLayoutAttributeLeading;
  _mainStack.spacing = 10;
  _mainStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
  _mainStack.translatesAutoresizingMaskIntoConstraints = NO;

  // Settings section (at top)
  [self addSettingsSection];

  // Separator between settings and controls
  NSBox* controlSep = [[NSBox alloc] init];
  controlSep.boxType = NSBoxSeparator;
  controlSep.translatesAutoresizingMaskIntoConstraints = NO;
  [_mainStack addArrangedSubview:controlSep];
  [NSLayoutConstraint activateConstraints:@[
    [controlSep.widthAnchor constraintEqualToAnchor:_mainStack.widthAnchor
                                           constant:-32],
  ]];

  // Status / spinner row
  NSStackView* statusRow = [[NSStackView alloc] init];
  statusRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  statusRow.spacing = 8;

  _spinner = [[NSProgressIndicator alloc] init];
  _spinner.style = NSProgressIndicatorStyleSpinning;
  _spinner.controlSize = NSControlSizeSmall;
  [_spinner setDisplayedWhenStopped:NO];

  _statusLabel =
      [NSTextField labelWithString:@"Detecting supported controls..."];
  _statusLabel.font = [NSFont systemFontOfSize:12];
  _statusLabel.textColor = [NSColor secondaryLabelColor];

  [statusRow addArrangedSubview:_spinner];
  [statusRow addArrangedSubview:_statusLabel];
  [_mainStack addArrangedSubview:statusRow];

  // Build all control rows (hidden by default)
  for (NSNumber* code in [DisplayController sliderAttributeCodes]) {
    [self addSliderRow:code.unsignedCharValue];
  }
  for (NSNumber* code in [DisplayController toggleAttributeCodes]) {
    [self addToggleRow:code.unsignedCharValue];
  }
  for (NSNumber* code in [DisplayController popupAttributeCodes]) {
    [self addPopupRow:code.unsignedCharValue];
  }
  for (NSNumber* code in [DisplayController buttonAttributeCodes]) {
    [self addButtonRow:code.unsignedCharValue];
  }

  // Scroll view wrapper
  NSScrollView* scrollView = [[NSScrollView alloc] init];
  scrollView.hasVerticalScroller = YES;
  scrollView.hasHorizontalScroller = NO;
  scrollView.autohidesScrollers = YES;
  scrollView.drawsBackground = NO;

  NSView* documentView = [[NSView alloc] init];
  documentView.translatesAutoresizingMaskIntoConstraints = NO;
  [documentView addSubview:_mainStack];

  scrollView.documentView = documentView;

  [NSLayoutConstraint activateConstraints:@[
    [_mainStack.topAnchor constraintEqualToAnchor:documentView.topAnchor],
    [_mainStack.leadingAnchor
        constraintEqualToAnchor:documentView.leadingAnchor],
    [_mainStack.trailingAnchor
        constraintEqualToAnchor:documentView.trailingAnchor],
    [_mainStack.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],
    [_mainStack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
  ]];

  self.window.contentView = scrollView;

  // Size window to fit the settings section + loading indicator
  [scrollView layoutSubtreeIfNeeded];
  NSSize contentSize = _mainStack.fittingSize;
  contentSize.width = 380;
  contentSize.height = fmin(contentSize.height + 20, 600);
  [self.window setContentSize:contentSize];
}

- (NSView*)createRowWithLabel:(NSString*)label
                      control:(NSView*)control
                   valueLabel:(NSTextField*)valLabel {
  NSStackView* row = [[NSStackView alloc] init];
  row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  row.spacing = 8;
  row.alignment = NSLayoutAttributeCenterY;

  NSTextField* nameLabel = [NSTextField labelWithString:label];
  nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
  [nameLabel setContentHuggingPriority:NSLayoutPriorityRequired
                        forOrientation:NSLayoutConstraintOrientationHorizontal];
  [NSLayoutConstraint activateConstraints:@[
    [nameLabel.widthAnchor constraintEqualToConstant:100],
  ]];

  [row addArrangedSubview:nameLabel];
  [row addArrangedSubview:control];
  if (valLabel != nullptr) {
    [NSLayoutConstraint activateConstraints:@[
      [valLabel.widthAnchor constraintEqualToConstant:40],
    ]];
    [row addArrangedSubview:valLabel];
  }

  row.hidden = YES;
  return row;
}

- (void)addSliderRow:(UInt8)attrCode {
  NSSlider* slider = [NSSlider sliderWithValue:0
                                      minValue:0
                                      maxValue:100
                                        target:self
                                        action:@selector(sliderChanged:)];
  slider.tag = attrCode;
  slider.continuous = YES;
  [NSLayoutConstraint activateConstraints:@[
    [slider.widthAnchor constraintGreaterThanOrEqualToConstant:180],
  ]];

  NSTextField* valLabel = [NSTextField labelWithString:@"0"];
  valLabel.alignment = NSTextAlignmentRight;
  valLabel.font = [NSFont monospacedDigitSystemFontOfSize:13
                                                   weight:NSFontWeightRegular];

  NSString* name = [DisplayController nameForAttribute:attrCode];
  NSView* row = [self createRowWithLabel:name
                                 control:slider
                              valueLabel:valLabel];

  _sliders[@(attrCode)] = slider;
  _valueLabels[@(attrCode)] = valLabel;
  _controlRows[@(attrCode)] = row;
  [_mainStack addArrangedSubview:row];
}

- (void)addToggleRow:(UInt8)attrCode {
  NSButton* toggle = [NSButton checkboxWithTitle:@""
                                          target:self
                                          action:@selector(toggleChanged:)];
  toggle.tag = attrCode;

  NSString* name = [DisplayController nameForAttribute:attrCode];
  NSView* row = [self createRowWithLabel:name control:toggle valueLabel:nil];

  _toggles[@(attrCode)] = toggle;
  _controlRows[@(attrCode)] = row;
  [_mainStack addArrangedSubview:row];
}

- (void)addPopupRow:(UInt8)attrCode {
  NSPopUpButton* popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect
                                                    pullsDown:NO];
  popup.tag = attrCode;
  popup.target = self;
  popup.action = @selector(popupChanged:);

  if (attrCode == INPUT) {
    // Use capabilities-derived options (or fallback) from DisplayController
    for (NSDictionary* opt in
         [_displayController inputOptionsForDisplayIndex:_displayIndex]) {
      [popup addItemWithTitle:opt[@"label"]];
      popup.lastItem.tag = [opt[@"value"] integerValue];
    }
  } else {
    const PopupOption* options = NULL;
    int count = 0;
    switch (attrCode) {
    case PBP:
      options = kPBPOptions;
      count = sizeof(kPBPOptions) / sizeof(kPBPOptions[0]);
      break;
    case PBP_INPUT:
      options = kPBPInputOptions;
      count = sizeof(kPBPInputOptions) / sizeof(kPBPInputOptions[0]);
      break;
    case KVM:
      options = kKVMOptions;
      count = sizeof(kKVMOptions) / sizeof(kKVMOptions[0]);
      break;
    }
    for (int i = 0; i < count; i++) {
      [popup addItemWithTitle:[NSString stringWithUTF8String:options[i].label]];
      popup.lastItem.tag = options[i].value;
    }
  }

  [popup.menu addItem:[NSMenuItem separatorItem]];
  [popup addItemWithTitle:@"Custom…"];
  popup.lastItem.tag = -1;

  NSString* name = [DisplayController nameForAttribute:attrCode];
  NSView* row = [self createRowWithLabel:name control:popup valueLabel:nil];

  _popups[@(attrCode)] = popup;
  _controlRows[@(attrCode)] = row;
  [_mainStack addArrangedSubview:row];
}

- (void)addButtonRow:(UInt8)attrCode {
  NSButton* button = [NSButton buttonWithTitle:@"Activate"
                                        target:self
                                        action:@selector(buttonPressed:)];
  button.tag = attrCode;
  button.bezelStyle = NSBezelStyleRounded;

  NSString* name = [DisplayController nameForAttribute:attrCode];
  NSView* row = [self createRowWithLabel:name control:button valueLabel:nil];

  _controlRows[@(attrCode)] = row;
  [_mainStack addArrangedSubview:row];
}

- (void)addSettingsSection {
  // Section header
  NSTextField* header = [NSTextField labelWithString:@"Display Settings"];
  header.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
  header.textColor = [NSColor secondaryLabelColor];
  [_mainStack addArrangedSubview:header];

  // Custom name
  NSString* uuid = [_displayController displayUUIDAtIndex:_displayIndex];
  NSString* customName = [_displayController customNameForUUID:uuid];

  _nameField = [[NSTextField alloc] init];
  _nameField.placeholderString =
      [_displayController displayNameAtIndex:_displayIndex];
  _nameField.stringValue = customName ?: @"";
  _nameField.translatesAutoresizingMaskIntoConstraints = NO;
  _nameField.delegate = self;
  [NSLayoutConstraint activateConstraints:@[
    [_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:180],
  ]];
  NSView* nameRow = [self createRowWithLabel:@"Name"
                                     control:_nameField
                                  valueLabel:nil];
  nameRow.hidden = NO;
  [_mainStack addArrangedSubview:nameRow];

  // Input profile
  _profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
  _profilePopup.target = self;
  _profilePopup.action = @selector(profileChanged:);

  BOOL altInput = [_displayController usesAlternateInputForIndex:_displayIndex];
  NSString* mfr = [_displayController manufacturerForIndex:_displayIndex];
  NSString* autoLabel = @"Auto";
  if (mfr.length > 0) {
    autoLabel = [NSString stringWithFormat:@"Auto – %@ (%@)", mfr,
                                           altInput ? @"LG" : @"Standard"];
  } else {
    autoLabel = [NSString
        stringWithFormat:@"Auto (%@)", altInput ? @"LG" : @"Standard"];
  }

  [_profilePopup addItemWithTitle:autoLabel];
  _profilePopup.lastItem.representedObject = @"auto";
  [_profilePopup addItemWithTitle:@"Standard"];
  _profilePopup.lastItem.representedObject = @"standard";
  [_profilePopup addItemWithTitle:@"LG / Alternate"];
  _profilePopup.lastItem.representedObject = @"lg";

  NSString* curProfile = [_displayController inputProfileForUUID:uuid];
  for (NSMenuItem* item in _profilePopup.itemArray) {
    if ([item.representedObject isEqualToString:curProfile]) {
      [_profilePopup selectItem:item];
      break;
    }
  }

  NSView* profileRow = [self createRowWithLabel:@"Input Profile"
                                        control:_profilePopup
                                     valueLabel:nil];
  profileRow.hidden = NO;
  [_mainStack addArrangedSubview:profileRow];
}

#pragma mark - Probing

- (void)probeAndRefresh {
  [_spinner startAnimation:nil];
  _statusLabel.stringValue = @"Detecting supported features...";
  _statusLabel.hidden = NO;

  int displayIndex = _displayIndex;
  UInt8 inputDDCCode =
      [_displayController inputAttributeCodeForIndex:_displayIndex];
  dispatch_async(_ddcQueue, ^{
    NSArray<NSNumber*>* supported =
        [self->_displayController probeAttributesForDisplayIndex:displayIndex];

    // Map INPUT_ALT → INPUT so the UI row matches
    NSMutableArray<NSNumber*>* mapped = [NSMutableArray array];
    for (NSNumber* code in supported) {
      if (code.unsignedCharValue == INPUT_ALT) {
        [mapped addObject:@(INPUT)];
      } else {
        [mapped addObject:code];
      }
    }

    // Read current values for supported attributes (use actual DDC codes)
    NSMutableDictionary<NSNumber*, NSValue*>* values =
        [NSMutableDictionary dictionary];
    for (NSNumber* code in mapped) {
      UInt8 ddcCode = code.unsignedCharValue;
      // For INPUT, use the display-specific DDC code
      if (ddcCode == INPUT)
        ddcCode = inputDDCCode;
      DDCValue val = [self->_displayController readAttribute:ddcCode
                                             forDisplayIndex:displayIndex];
      values[code] = [NSValue valueWithBytes:&val objCType:@encode(DDCValue)];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateUIWithSupportedAttributes:mapped values:values];
    });
  });
}

- (void)updateUIWithSupportedAttributes:(NSArray<NSNumber*>*)supported
                                 values:(NSDictionary<NSNumber*, NSValue*>*)
                                            values {
  [_spinner stopAnimation:nil];
  NSSet* supportedSet = [NSSet setWithArray:supported];

  if (supported.count == 0) {
    _statusLabel.stringValue = @"No supported features detected.";
    return;
  }
  _statusLabel.hidden = YES;

  for (NSNumber* code in _controlRows) {
    NSView* row = _controlRows[code];
    BOOL isSupported = [supportedSet containsObject:code];
    row.hidden = !isSupported;

    if (!isSupported)
      continue;

    DDCValue val;
    [values[code] getValue:&val];

    UInt8 attrCode = code.unsignedCharValue;

    // Update slider
    NSSlider* slider = _sliders[code];
    if (slider) {
      slider.maxValue = val.maxValue > 0 ? val.maxValue : 100;
      slider.integerValue = val.curValue;
      _valueLabels[code].stringValue =
          [NSString stringWithFormat:@"%d", val.curValue];
    }

    // Update toggle (mute: 1=on, 2=off)
    NSButton* toggle = _toggles[code];
    if (toggle) {
      toggle.state =
          (val.curValue == 1) ? NSControlStateValueOn : NSControlStateValueOff;
    }

    // Update popup - select item matching current value
    NSPopUpButton* popup = _popups[code];
    if (popup) {
      BOOL found = NO;
      for (NSMenuItem* item in popup.itemArray) {
        if (item.tag == val.curValue) {
          [popup selectItem:item];
          found = YES;
          break;
        }
      }
      if (!found && val.curValue >= 0) {
        // Add a "Current: X" entry if value doesn't match known options
        NSString* title =
            [NSString stringWithFormat:@"Current (%d)", val.curValue];
        [popup addItemWithTitle:title];
        popup.lastItem.tag = val.curValue;
        [popup selectItem:popup.lastItem];
      }
    }
  }

  // Resize window to fit content
  [self.window.contentView layoutSubtreeIfNeeded];
  NSSize contentSize = _mainStack.fittingSize;
  contentSize.width = 380;
  contentSize.height = fmin(contentSize.height + 20, 600);
  [self.window setContentSize:contentSize];
}

- (UInt8)resolvedDDCCode:(UInt8)attrCode {
  // Translate logical INPUT to the actual DDC code for this display
  if (attrCode == INPUT)
    return [_displayController inputAttributeCodeForIndex:_displayIndex];
  return attrCode;
}

#pragma mark - Actions

- (void)sliderChanged:(NSSlider*)sender {
  UInt8 attrCode = (UInt8)sender.tag;
  UInt8 ddcCode = [self resolvedDDCCode:attrCode];
  UInt16 newValue = (UInt16)sender.integerValue;

  _valueLabels[@(attrCode)].stringValue =
      [NSString stringWithFormat:@"%d", newValue];

  // Debounce DDC writes
  [_debounceTimers[@(attrCode)] invalidate];
  _debounceTimers[@(attrCode)] = [NSTimer
      scheduledTimerWithTimeInterval:0.1
                             repeats:NO
                               block:^(NSTimer* timer __unused) {
                                 dispatch_async(self->_ddcQueue, ^{
                                   [self->_displayController
                                        writeAttribute:ddcCode
                                                 value:newValue
                                       forDisplayIndex:self->_displayIndex];
                                 });
                               }];
}

- (void)toggleChanged:(NSButton*)sender {
  UInt8 attrCode = (UInt8)sender.tag;
  UInt8 ddcCode = [self resolvedDDCCode:attrCode];
  // Mute: on=1, off=2 per DDC convention
  UInt16 newValue = (sender.state == NSControlStateValueOn) ? 1 : 2;

  dispatch_async(_ddcQueue, ^{
    [self->_displayController writeAttribute:ddcCode
                                       value:newValue
                             forDisplayIndex:self->_displayIndex];
  });
}

- (void)popupChanged:(NSPopUpButton*)sender {
  UInt8 attrCode = (UInt8)sender.tag;
  UInt8 ddcCode = [self resolvedDDCCode:attrCode];

  if (sender.selectedItem.tag == -1) {
    // "Custom…" selected — prompt for a raw value
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = [NSString
        stringWithFormat:@"Custom %@",
                         [DisplayController nameForAttribute:attrCode]];
    alert.informativeText = @"Enter the raw DDC value:";
    [alert addButtonWithTitle:@"Set"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField* input =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
      UInt16 customValue = (UInt16)input.integerValue;
      // Add/update the custom entry in the popup
      NSString* title = [NSString stringWithFormat:@"Custom (%d)", customValue];
      // Remove previous custom value entries (but not "Custom…")
      NSMutableArray* toRemove = [NSMutableArray array];
      for (NSMenuItem* item in sender.itemArray) {
        if ([item.title hasPrefix:@"Custom ("] ||
            [item.title hasPrefix:@"Current ("]) {
          [toRemove addObject:item];
        }
      }
      for (NSMenuItem* item in toRemove) {
        [sender.menu removeItem:item];
      }
      // Insert before the separator + "Custom…"
      NSInteger customIdx = [sender.menu indexOfItem:sender.lastItem];
      [sender.menu insertItemWithTitle:title
                                action:nil
                         keyEquivalent:@""
                               atIndex:customIdx];
      sender.itemArray[customIdx].tag = customValue;
      [sender selectItemAtIndex:customIdx];

      dispatch_async(_ddcQueue, ^{
        [self->_displayController writeAttribute:ddcCode
                                           value:customValue
                                 forDisplayIndex:self->_displayIndex];
      });
    } else {
      // Cancelled — reselect previous item (first selected known item)
      // Just select the first item as fallback
      if (sender.numberOfItems > 1) {
        [sender selectItemAtIndex:0];
      }
    }
    return;
  }

  UInt16 newValue = (UInt16)sender.selectedItem.tag;
  dispatch_async(_ddcQueue, ^{
    [self->_displayController writeAttribute:ddcCode
                                       value:newValue
                             forDisplayIndex:self->_displayIndex];
  });
}

- (void)buttonPressed:(NSButton*)sender {
  UInt8 attrCode = (UInt8)sender.tag;
  UInt8 ddcCode = [self resolvedDDCCode:attrCode];
  UInt16 value = 5; // Standby value

  dispatch_async(_ddcQueue, ^{
    [self->_displayController writeAttribute:ddcCode
                                       value:value
                             forDisplayIndex:self->_displayIndex];
  });
}

- (void)controlTextDidChange:(NSNotification*)notification {
  NSTextField* field = notification.object;
  if (field != _nameField)
    return;

  NSString* uuid = [_displayController displayUUIDAtIndex:_displayIndex];
  NSString* newName = field.stringValue;
  NSString* productName = [_displayController displayNameAtIndex:_displayIndex];

  if (newName.length == 0 || [newName isEqualToString:productName]) {
    [_displayController setCustomName:nil forUUID:uuid];
  } else {
    [_displayController setCustomName:newName forUUID:uuid];
  }

  // Update window title and notify tray menu
  self.window.title = [_displayController displayLabelAtIndex:_displayIndex];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:@"DisplaySettingsDidChange"
                    object:nil];
}

- (void)profileChanged:(NSPopUpButton*)sender {
  NSString* uuid = [_displayController displayUUIDAtIndex:_displayIndex];
  NSString* profile = sender.selectedItem.representedObject;

  [_displayController setInputProfile:profile forUUID:uuid];
  [[NSNotificationCenter defaultCenter]
      postNotificationName:@"DisplaySettingsDidChange"
                    object:nil];
}

@end
