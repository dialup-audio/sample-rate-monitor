cmake_minimum_required(VERSION 3.20)
project(sample_rate_display LANGUAGES OBJCXX)

set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

add_executable(sample-rate-display
    main.mm
)

target_compile_options(sample-rate-display PRIVATE -fobjc-arc)

target_link_libraries(sample-rate-display
    "-framework Cocoa"
    "-framework Foundation"
    "-framework CoreAudio"
)

set_target_properties(sample-rate-display PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    MACOSX_BUNDLE_BUNDLE_NAME "kHzDisp"
    MACOSX_BUNDLE_GUI_IDENTIFIER "dialup.audio.khzdisp"
)
