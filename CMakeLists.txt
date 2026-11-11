cmake_minimum_required(VERSION 3.20)
project(rew_spl_menubar LANGUAGES OBJCXX)

set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

add_executable(dock-sample-rate-display
    main.mm
)

target_link_libraries(dock-sample-rate-display
    "-framework Cocoa"
    "-framework Foundation"
)

set_target_properties(dock-sample-rate-display PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "REW SPL"
    MACOSX_BUNDLE_GUI_IDENTIFIER "online.freeaol.dock-samplerate-menubar"
)
