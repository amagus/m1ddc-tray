cmake_minimum_required(VERSION 3.20)
project(m1ddc-tray LANGUAGES C OBJC OBJCXX)

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJCXX_STANDARD 17)

# --- Check submodule ---
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/m1ddc/sources/i2c.m")
    message(FATAL_ERROR
        "m1ddc submodule not found. "
        "Maybe you cloned without `--recursive`? "
        "Run `git submodule update --init` to fix this.")
endif()

# --- Static library: m1ddc_lib (Objective-C) ---
add_library(m1ddc_lib STATIC
    m1ddc/sources/i2c.m
    m1ddc/sources/ioregistry.m
)
target_include_directories(m1ddc_lib PUBLIC m1ddc/headers)
target_compile_options(m1ddc_lib PRIVATE -fmodules)
target_link_libraries(m1ddc_lib PUBLIC
    "-framework CoreDisplay"
    "-framework IOKit"
    "-framework CoreGraphics"
    "-framework Foundation"
)

# --- App bundle: m1ddc-tray (Objective-C++) ---
add_executable(m1ddc-tray MACOSX_BUNDLE
    app/main.mm
    app/AppDelegate.mm
    app/DisplayController.mm
    app/ControlWindowController.mm
    app/PresetManager.mm
    app/PresetWindowController.mm
)
target_include_directories(m1ddc-tray PRIVATE m1ddc/headers app)
target_compile_options(m1ddc-tray PRIVATE -fmodules -fcxx-modules -fobjc-arc)
target_link_libraries(m1ddc-tray PRIVATE
    m1ddc_lib
    "-framework AppKit"
)

# --- App icon ---
set(APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/AppIcon.icns")
set_source_files_properties(${APP_ICON} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
target_sources(m1ddc-tray PRIVATE ${APP_ICON})

# --- Info.plist ---
set(MACOSX_BUNDLE_GUI_IDENTIFIER "com.amagus.m1ddc-tray")
set(MACOSX_BUNDLE_BUNDLE_NAME "m1ddc-tray")
set(MACOSX_BUNDLE_BUNDLE_VERSION "1.0.0")
set(MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.0")
configure_file(resources/Info.plist.in
    "${CMAKE_CURRENT_BINARY_DIR}/Info.plist" @ONLY)
set_target_properties(m1ddc-tray PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
)

# --- Codesigning (optional) ---
if(APPLE_CODESIGN_DEV)
    add_custom_command(TARGET m1ddc-tray POST_BUILD
        COMMAND codesign --force --sign "${APPLE_CODESIGN_DEV}"
                --deep "$<TARGET_BUNDLE_DIR:m1ddc-tray>"
        COMMENT "Codesigning m1ddc-tray.app with identity: ${APPLE_CODESIGN_DEV}"
        VERBATIM
    )
endif()
