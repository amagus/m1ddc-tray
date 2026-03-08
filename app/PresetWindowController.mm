@import AppKit;
#import "PresetWindowController.h"

#pragma mark - Action Row View

@interface ActionRowView : NSStackView
@property (nonatomic, strong) NSPopUpButton *displayPopup;
@property (nonatomic, strong) NSPopUpButton *attributePopup;
@property (nonatomic, strong) NSTextField *valueField;
@property (nonatomic, strong) NSPopUpButton *valuePopup;
@property (nonatomic, strong) NSButton *removeButton;
@end

@implementation ActionRowView
@end

// Popup options for preset value editor (same as ControlWindowController)
typedef struct {
    const char *label;
    UInt16 value;
} PresetPopupOption;

static const PresetPopupOption kPresetInputOptions[] = {
    {"DisplayPort 1", 15}, {"DisplayPort 2", 16},
    {"HDMI 1", 17}, {"HDMI 2", 18}, {"USB-C", 27},
};

static const PresetPopupOption kPresetInputAltOptions[] = {
    {"DisplayPort 1", 208}, {"DisplayPort 2", 209},
    {"HDMI 1", 144}, {"HDMI 2", 145}, {"USB-C / DP 3", 210},
};

static const PresetPopupOption kPresetPBPOptions[] = {
    {"Off", 0}, {"Small Window", 33}, {"Large Window", 34},
    {"50/50 Split", 36}, {"26/74 Split", 43}, {"74/26 Split", 44}, {"2x2", 65},
};

static const PresetPopupOption kPresetPBPInputOptions[] = {
    {"DisplayPort 1", 15}, {"DisplayPort 2", 16},
    {"HDMI 1", 17}, {"HDMI 2", 18},
};

static const PresetPopupOption kPresetKVMOptions[] = {
    {"USB 1-2-3-4", 1728}, {"Next Device", 65280},
};

#pragma mark - PresetWindowController

@interface PresetWindowController () <NSTableViewDelegate, NSTableViewDataSource>
@property (nonatomic, strong) PresetManager *presetManager;
@property (nonatomic, strong) DisplayController *displayController;
@property (nonatomic, strong) NSMutableArray<Preset *> *presets;
@property (nonatomic, strong) NSTableView *presetTable;
@property (nonatomic, strong) NSTextField *nameField;
@property (nonatomic, strong) NSStackView *actionsStack;
@property (nonatomic, strong) NSScrollView *actionsScrollView;
@property (nonatomic, strong) NSMutableArray<ActionRowView *> *actionRows;
@property (nonatomic, assign) NSInteger selectedPresetIndex;
@end

@implementation PresetWindowController

- (instancetype)initWithPresetManager:(PresetManager *)presetManager
                    displayController:(DisplayController *)displayController {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 650, 450)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];

    window.title = @"Edit Presets";
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(550, 350);
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        _presetManager = presetManager;
        _displayController = displayController;
        _presets = [[presetManager allPresets] mutableCopy];
        _actionRows = [NSMutableArray array];
        _selectedPresetIndex = -1;
        [self buildUI];
    }
    return self;
}

#pragma mark - UI Construction

- (void)buildUI {
    NSSplitView *splitView = [[NSSplitView alloc] init];
    splitView.dividerStyle = NSSplitViewDividerStyleThin;
    splitView.vertical = YES;
    splitView.translatesAutoresizingMaskIntoConstraints = NO;

    // Left panel: preset list
    NSView *leftPanel = [self buildPresetListPanel];
    // Right panel: preset editor
    NSView *rightPanel = [self buildPresetEditorPanel];

    [splitView addArrangedSubview:leftPanel];
    [splitView addArrangedSubview:rightPanel];

    self.window.contentView = splitView;

    [NSLayoutConstraint activateConstraints:@[
        [leftPanel.widthAnchor constraintGreaterThanOrEqualToConstant:180],
        [rightPanel.widthAnchor constraintGreaterThanOrEqualToConstant:350],
    ]];

    [splitView setPosition:200 ofDividerAtIndex:0];
}

- (NSView *)buildPresetListPanel {
    NSView *panel = [[NSView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    // Table view for presets
    NSScrollView *scrollView = [[NSScrollView alloc] init];
    scrollView.hasVerticalScroller = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _presetTable = [[NSTableView alloc] init];
    _presetTable.delegate = self;
    _presetTable.dataSource = self;
    _presetTable.headerView = nil;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.title = @"Presets";
    [_presetTable addTableColumn:column];
    scrollView.documentView = _presetTable;

    // Add / Remove buttons
    NSButton *addButton = [NSButton buttonWithTitle:@"+" target:self action:@selector(addPreset:)];
    NSButton *removeButton = [NSButton buttonWithTitle:@"−" target:self action:@selector(removePreset:)];
    addButton.bezelStyle = NSBezelStyleSmallSquare;
    removeButton.bezelStyle = NSBezelStyleSmallSquare;

    NSStackView *buttonBar = [NSStackView stackViewWithViews:@[addButton, removeButton]];
    buttonBar.spacing = 0;
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;

    [panel addSubview:scrollView];
    [panel addSubview:buttonBar];

    CGFloat bottomPadding = 6;
    CGFloat sidePadding = 6;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:buttonBar.topAnchor constant:-4],
        [buttonBar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:sidePadding],
        [buttonBar.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-bottomPadding],
        [buttonBar.heightAnchor constraintEqualToConstant:24],
    ]];

    return panel;
}

- (NSView *)buildPresetEditorPanel {
    CGFloat pad = 12;

    NSView *panel = [[NSView alloc] init];
    panel.translatesAutoresizingMaskIntoConstraints = NO;

    // Name row
    NSTextField *nameLabel = [NSTextField labelWithString:@"Name:"];
    nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField = [[NSTextField alloc] init];
    _nameField.placeholderString = @"Preset name";
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;

    // Actions header
    NSTextField *actionsHeader = [NSTextField labelWithString:@"Actions:"];
    actionsHeader.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    actionsHeader.translatesAutoresizingMaskIntoConstraints = NO;

    // Actions scroll view
    _actionsScrollView = [[NSScrollView alloc] init];
    _actionsScrollView.hasVerticalScroller = YES;
    _actionsScrollView.hasHorizontalScroller = NO;
    _actionsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _actionsScrollView.drawsBackground = NO;

    _actionsStack = [[NSStackView alloc] init];
    _actionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _actionsStack.spacing = 6;
    _actionsStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *actionsDoc = [[NSView alloc] init];
    actionsDoc.translatesAutoresizingMaskIntoConstraints = NO;
    [actionsDoc addSubview:_actionsStack];
    _actionsScrollView.documentView = actionsDoc;

    [NSLayoutConstraint activateConstraints:@[
        [_actionsStack.topAnchor constraintEqualToAnchor:actionsDoc.topAnchor constant:4],
        [_actionsStack.leadingAnchor constraintEqualToAnchor:actionsDoc.leadingAnchor],
        [_actionsStack.trailingAnchor constraintEqualToAnchor:actionsDoc.trailingAnchor],
        [_actionsStack.bottomAnchor constraintEqualToAnchor:actionsDoc.bottomAnchor],
        [_actionsStack.widthAnchor constraintEqualToAnchor:_actionsScrollView.widthAnchor constant:-20],
    ]];

    // Bottom bar
    NSButton *addActionButton = [NSButton buttonWithTitle:@"Add Action"
                                                  target:self action:@selector(addAction:)];
    NSButton *saveButton = [NSButton buttonWithTitle:@"Save"
                                              target:self action:@selector(savePreset:)];
    saveButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";

    NSStackView *bottomBar = [NSStackView stackViewWithViews:@[addActionButton, saveButton]];
    bottomBar.spacing = 8;
    bottomBar.translatesAutoresizingMaskIntoConstraints = NO;

    // Add all subviews
    [panel addSubview:nameLabel];
    [panel addSubview:_nameField];
    [panel addSubview:actionsHeader];
    [panel addSubview:_actionsScrollView];
    [panel addSubview:bottomBar];

    // Pin everything with explicit constraints — scroll view fills remaining space
    [NSLayoutConstraint activateConstraints:@[
        // Name row
        [nameLabel.topAnchor constraintEqualToAnchor:panel.topAnchor constant:pad],
        [nameLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [_nameField.centerYAnchor constraintEqualToAnchor:nameLabel.centerYAnchor],
        [_nameField.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor constant:8],
        [_nameField.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad],

        // Actions header
        [actionsHeader.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:10],
        [actionsHeader.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],

        // Actions scroll view — fills all remaining space
        [_actionsScrollView.topAnchor constraintEqualToAnchor:actionsHeader.bottomAnchor constant:6],
        [_actionsScrollView.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [_actionsScrollView.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-pad],
        [_actionsScrollView.bottomAnchor constraintEqualToAnchor:bottomBar.topAnchor constant:-10],

        // Bottom bar — pinned to bottom
        [bottomBar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:pad],
        [bottomBar.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-pad],
    ]];

    return panel;
}

#pragma mark - Action Row Management

- (BOOL)isPopupAttribute:(UInt8)attrCode {
    static NSSet *popupCodes = nil;
    if (!popupCodes) {
        popupCodes = [NSSet setWithArray:[DisplayController popupAttributeCodes]];
    }
    return [popupCodes containsObject:@(attrCode)];
}

- (void)populateValuePopup:(NSPopUpButton *)popup forAttribute:(UInt8)attrCode withValue:(UInt16)value {
    [popup removeAllItems];

    const PresetPopupOption *options = NULL;
    int count = 0;

    switch (attrCode) {
        case INPUT:
            options = kPresetInputOptions;
            count = sizeof(kPresetInputOptions) / sizeof(kPresetInputOptions[0]);
            break;
        case INPUT_ALT:
            options = kPresetInputAltOptions;
            count = sizeof(kPresetInputAltOptions) / sizeof(kPresetInputAltOptions[0]);
            break;
        case PBP:
            options = kPresetPBPOptions;
            count = sizeof(kPresetPBPOptions) / sizeof(kPresetPBPOptions[0]);
            break;
        case PBP_INPUT:
            options = kPresetPBPInputOptions;
            count = sizeof(kPresetPBPInputOptions) / sizeof(kPresetPBPInputOptions[0]);
            break;
        case KVM:
            options = kPresetKVMOptions;
            count = sizeof(kPresetKVMOptions) / sizeof(kPresetKVMOptions[0]);
            break;
    }

    BOOL found = NO;
    for (int i = 0; i < count; i++) {
        NSString *title = [NSString stringWithUTF8String:options[i].label];
        [popup addItemWithTitle:title];
        popup.lastItem.tag = options[i].value;
        if (options[i].value == value) {
            [popup selectItem:popup.lastItem];
            found = YES;
        }
    }

    [popup.menu addItem:[NSMenuItem separatorItem]];
    [popup addItemWithTitle:@"Custom…"];
    popup.lastItem.tag = -1;

    if (!found && value > 0) {
        NSString *title = [NSString stringWithFormat:@"Custom (%d)", value];
        NSInteger idx = [popup.menu indexOfItem:popup.lastItem];
        [popup.menu insertItemWithTitle:title action:nil keyEquivalent:@"" atIndex:idx];
        popup.itemArray[idx].tag = value;
        [popup selectItemAtIndex:idx];
    }
}

- (void)updateValueControlForRow:(ActionRowView *)row withValue:(UInt16)value {
    UInt8 attrCode = (UInt8)row.attributePopup.selectedItem.tag;

    if ([self isPopupAttribute:attrCode]) {
        // Show value popup, hide value field
        row.valueField.hidden = YES;
        row.valuePopup.hidden = NO;
        [self populateValuePopup:row.valuePopup forAttribute:attrCode withValue:value];
    } else {
        // Show value field, hide value popup
        row.valueField.hidden = NO;
        row.valuePopup.hidden = YES;
        if (value > 0) {
            row.valueField.stringValue = [NSString stringWithFormat:@"%d", value];
        } else {
            row.valueField.stringValue = @"";
        }
    }
}

- (ActionRowView *)createActionRow:(PresetAction *)action {
    ActionRowView *row = [[ActionRowView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 6;
    row.alignment = NSLayoutAttributeCenterY;

    // Display popup
    row.displayPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    row.displayPopup.translatesAutoresizingMaskIntoConstraints = NO;
    for (int i = 0; i < _displayController.displayCount; i++) {
        NSString *name = [_displayController displayLabelAtIndex:i];
        [row.displayPopup addItemWithTitle:name];
        row.displayPopup.lastItem.representedObject = [_displayController displayUUIDAtIndex:i];
    }
    if (action) {
        for (NSMenuItem *item in row.displayPopup.itemArray) {
            if ([item.representedObject isEqualToString:action.displayUUID]) {
                [row.displayPopup selectItem:item];
                break;
            }
        }
    }

    // Attribute popup
    row.attributePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    row.attributePopup.translatesAutoresizingMaskIntoConstraints = NO;
    row.attributePopup.target = self;
    row.attributePopup.action = @selector(presetAttributeChanged:);
    for (NSNumber *code in [DisplayController allAttributeCodes]) {
        NSString *name = [DisplayController nameForAttribute:code.unsignedCharValue];
        [row.attributePopup addItemWithTitle:name];
        row.attributePopup.lastItem.tag = code.unsignedCharValue;
    }
    if (action) {
        for (NSMenuItem *item in row.attributePopup.itemArray) {
            if (item.tag == action.attributeCode) {
                [row.attributePopup selectItem:item];
                break;
            }
        }
    }

    // Value field (for slider/toggle/button attributes)
    row.valueField = [[NSTextField alloc] init];
    row.valueField.placeholderString = @"Value";
    row.valueField.translatesAutoresizingMaskIntoConstraints = NO;

    // Value popup (for popup attributes like Input, PBP, etc.)
    row.valuePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    row.valuePopup.translatesAutoresizingMaskIntoConstraints = NO;
    row.valuePopup.target = self;
    row.valuePopup.action = @selector(presetValuePopupChanged:);

    // Remove button
    row.removeButton = [NSButton buttonWithTitle:@"✕" target:self action:@selector(removeAction:)];
    row.removeButton.bezelStyle = NSBezelStyleInline;
    row.removeButton.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [row.displayPopup.widthAnchor constraintEqualToConstant:150],
        [row.attributePopup.widthAnchor constraintEqualToConstant:140],
        [row.valueField.widthAnchor constraintEqualToConstant:60],
        [row.valuePopup.widthAnchor constraintEqualToConstant:150],
        [row.removeButton.widthAnchor constraintEqualToConstant:24],
    ]];

    [row addArrangedSubview:row.displayPopup];
    [row addArrangedSubview:row.attributePopup];
    [row addArrangedSubview:row.valueField];
    [row addArrangedSubview:row.valuePopup];
    [row addArrangedSubview:row.removeButton];

    // Set the correct value control based on the attribute type
    UInt16 val = action ? action.value : 0;
    [self updateValueControlForRow:row withValue:val];

    return row;
}

- (void)loadPresetAtIndex:(NSInteger)index {
    _selectedPresetIndex = index;

    // Clear existing action rows
    for (ActionRowView *row in _actionRows) {
        [row removeFromSuperview];
    }
    [_actionRows removeAllObjects];

    if (index < 0 || index >= (NSInteger)_presets.count) {
        _nameField.stringValue = @"";
        _nameField.enabled = NO;
        return;
    }

    _nameField.enabled = YES;
    Preset *preset = _presets[index];
    _nameField.stringValue = preset.name ?: @"";

    for (PresetAction *action in preset.actions) {
        ActionRowView *row = [self createActionRow:action];
        [_actionsStack addArrangedSubview:row];
        [_actionRows addObject:row];
    }
}

- (PresetAction *)actionFromRow:(ActionRowView *)row {
    PresetAction *action = [[PresetAction alloc] init];
    action.displayUUID = row.displayPopup.selectedItem.representedObject ?: @"";
    action.attributeCode = (UInt8)row.attributePopup.selectedItem.tag;
    if ([self isPopupAttribute:action.attributeCode]) {
        action.value = (UInt16)row.valuePopup.selectedItem.tag;
    } else {
        action.value = (UInt16)row.valueField.integerValue;
    }
    return action;
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)_presets.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    return _presets[row].name ?: @"Untitled";
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self loadPresetAtIndex:_presetTable.selectedRow];
}

#pragma mark - Actions

- (void)addPreset:(id)sender {
    (void)sender;
    Preset *preset = [[Preset alloc] init];
    preset.name = @"New Preset";
    [_presets addObject:preset];
    [_presetTable reloadData];
    [_presetTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_presets.count - 1]
              byExtendingSelection:NO];
}

- (void)removePreset:(id)sender {
    (void)sender;
    NSInteger row = _presetTable.selectedRow;
    if (row < 0) return;

    Preset *preset = _presets[row];
    [_presetManager deletePreset:preset.identifier];
    [_presets removeObjectAtIndex:row];
    [_presetTable reloadData];
    [self loadPresetAtIndex:-1];
}

- (void)addAction:(id)sender {
    (void)sender;
    if (_selectedPresetIndex < 0) return;

    ActionRowView *row = [self createActionRow:nil];
    [_actionsStack addArrangedSubview:row];
    [_actionRows addObject:row];
}

- (void)presetAttributeChanged:(NSPopUpButton *)sender {
    // Find the ActionRowView containing this popup
    for (ActionRowView *row in _actionRows) {
        if (row.attributePopup == sender) {
            [self updateValueControlForRow:row withValue:0];
            break;
        }
    }
}

- (void)presetValuePopupChanged:(NSPopUpButton *)sender {
    if (sender.selectedItem.tag != -1) return;

    // "Custom…" selected — prompt for a raw value
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Custom Value";
    alert.informativeText = @"Enter the raw DDC value:";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
    alert.accessoryView = input;
    [alert.window makeFirstResponder:input];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        UInt16 customValue = (UInt16)input.integerValue;
        NSString *title = [NSString stringWithFormat:@"Custom (%d)", customValue];
        // Remove previous custom entries
        NSMutableArray *toRemove = [NSMutableArray array];
        for (NSMenuItem *item in sender.itemArray) {
            if ([item.title hasPrefix:@"Custom ("]) {
                [toRemove addObject:item];
            }
        }
        for (NSMenuItem *item in toRemove) {
            [sender.menu removeItem:item];
        }
        NSInteger idx = [sender.menu indexOfItem:sender.lastItem];
        [sender.menu insertItemWithTitle:title action:nil keyEquivalent:@"" atIndex:idx];
        sender.itemArray[idx].tag = customValue;
        [sender selectItemAtIndex:idx];
    } else {
        if (sender.numberOfItems > 1) {
            [sender selectItemAtIndex:0];
        }
    }
}

- (void)removeAction:(NSButton *)sender {
    for (ActionRowView *row in _actionRows) {
        if (row.removeButton == sender) {
            [row removeFromSuperview];
            [_actionRows removeObject:row];
            break;
        }
    }
}

- (void)savePreset:(id)sender {
    (void)sender;
    if (_selectedPresetIndex < 0 || _selectedPresetIndex >= (NSInteger)_presets.count) return;

    Preset *preset = _presets[_selectedPresetIndex];
    preset.name = _nameField.stringValue;
    [preset.actions removeAllObjects];

    for (ActionRowView *row in _actionRows) {
        [preset.actions addObject:[self actionFromRow:row]];
    }

    [_presetManager savePreset:preset];
    [_presetTable reloadData];

    // Post notification so the menu bar can update
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PresetsDidChange" object:nil];
}

@end
