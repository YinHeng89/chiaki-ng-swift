cmake_minimum_required(VERSION 3.20)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Minimum macOS or iOS version")
project(ChiakiNGCore LANGUAGES C CXX OBJC)

set(LIBCHIAKING_CURL ON CACHE BOOL "libchiaking curl provider" FORCE)
set(LIBCHIAKING_CRYPTO_OPENSSL ON CACHE BOOL "libchiaking OpenSSL provider" FORCE)
if(CMAKE_CROSSCOMPILING)
    set(LIBCHIAKING_BUILD_TESTS OFF CACHE BOOL "libchiaking tests" FORCE)
else()
    set(LIBCHIAKING_BUILD_TESTS ON CACHE BOOL "libchiaking tests" FORCE)
endif()
option(LIBCHIAKING_KAKUSAN "Build Kakusan, which lets invited players join a live play session" ON)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/chiaki-ng-core" libchiaking)
enable_testing()
include(SDL.cmake)

add_library(ChiakiBridge OBJECT bridge/opened.cpp bridge/runtime.cpp bridge/account_ids.cpp
    bridge/console_ids.cpp bridge/core/core_session.cpp bridge/consoles/pairing_bridge.cpp bridge/core/request.cpp bridge/users/users_bridge.cpp
    bridge/users/credentials_bridge.cpp bridge/consoles/consoles_bridge.cpp
    bridge/consoles/discovery_bridge.cpp bridge/consoles/console_titles_bridge.cpp
    bridge/consoles/account_consoles_bridge.cpp
    bridge/consoles/game_invitations_bridge.cpp
    bridge/messages/messages_bridge.cpp
    bridge/trophies/trophies_bridge.cpp
    bridge/sharing/session_sharing_bridge.cpp
    bridge/network/network_bridge.cpp
    bridge/stream_session.cpp bridge/audio_path.cpp bridge/controller_speaker_mix.cpp bridge/feedback_path.cpp bridge/audio.cpp bridge/audio_engine.m
    bridge/bridge_log.cpp bridge/catalog/caches_bridge.cpp bridge/catalog/catalog_bridge.cpp
    bridge/catalog/title_checks_bridge.cpp
    bridge/diagnostics/http_calls_bridge.cpp bridge/diagnostics/core_log_bridge.cpp
    bridge/media/motion_fusion.cpp bridge/media/microphone_encoder.cpp bridge/media/microphone_queue.cpp bridge/media/console_feedback.cpp
    bridge/media/haptic_rumble.cpp bridge/media/haptic_audio.cpp bridge/media/audio_outputs.cpp
    bridge/play/play_bridge.cpp)
if(LIBCHIAKING_KAKUSAN)
    target_sources(ChiakiBridge PRIVATE bridge/share_desk.cpp bridge/share_relay.cpp bridge/kakusan/kakusan_devices.cpp)
endif()
set(chiaki_kakusan_definition CHIAKI_KAKUSAN=$<BOOL:${LIBCHIAKING_KAKUSAN}>)
target_compile_definitions(ChiakiBridge PUBLIC ${chiaki_kakusan_definition})
target_include_directories(ChiakiBridge PUBLIC bridge bridge/include)
target_compile_features(ChiakiBridge PUBLIC cxx_std_20)
target_link_libraries(ChiakiBridge PUBLIC SDL3::SDL3 libchiaking::default_platform libchiaking::chiaki_ng libchiaking::libchiaking
    libchiaking::media_opus "-framework CoreVideo")
target_compile_options(ChiakiBridge PRIVATE -Werror=switch)
set_source_files_properties(bridge/audio_engine.m PROPERTIES COMPILE_OPTIONS -fobjc-arc)
target_link_libraries(ChiakiBridge PUBLIC "-framework Foundation" "-framework AVFoundation" "-framework AudioToolbox")
if(APPLE AND NOT IOS)
    target_link_libraries(ChiakiBridge PUBLIC "-framework CoreAudio")
endif()
set_target_properties(ChiakiBridge PROPERTIES OSX_DEPLOYMENT_TARGET 26.0 CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON)

add_library(ChiakiRegistration SHARED $<TARGET_OBJECTS:ChiakiBridge>)
target_include_directories(ChiakiRegistration PUBLIC bridge/include)
target_compile_definitions(ChiakiRegistration PUBLIC ${chiaki_kakusan_definition})
target_link_libraries(ChiakiRegistration PRIVATE ChiakiBridge)
set_target_properties(ChiakiRegistration PROPERTIES OSX_DEPLOYMENT_TARGET 26.0 LINKER_LANGUAGE CXX
    INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE)

if(CMAKE_CROSSCOMPILING)
    return()
endif()

function(chiaki_bridge_test name source)
    add_executable(${name} ../Tests/Native/NativeCoreTests/${source})
    target_compile_options(${name} PRIVATE -UNDEBUG)
    set_target_properties(${name} PROPERTIES OSX_DEPLOYMENT_TARGET 26.0)
    target_link_libraries(${name} PRIVATE ChiakiRegistration)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

function(chiaki_bridge_unit_test name source)
    add_executable(${name} ../Tests/Native/NativeCoreTests/${source} $<TARGET_OBJECTS:ChiakiBridge>)
    target_compile_options(${name} PRIVATE -UNDEBUG)
    set_target_properties(${name} PROPERTIES OSX_DEPLOYMENT_TARGET 26.0 CXX_EXTENSIONS OFF)
    target_link_libraries(${name} PRIVATE ChiakiBridge)
    add_test(NAME ${name} COMMAND ${name})
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "SDL_AUDIODRIVER=dummy")
endfunction()

chiaki_bridge_test(chiaki-domains-test domains.cpp)
set_target_properties(chiaki-domains-test PROPERTIES CXX_STANDARD 23 CXX_STANDARD_REQUIRED ON)
target_include_directories(chiaki-domains-test PRIVATE bridge/include
    $<TARGET_PROPERTY:libchiaking::libchiaking,INTERFACE_INCLUDE_DIRECTORIES>)
set_tests_properties(chiaki-domains-test PROPERTIES ENVIRONMENT "SDL_AUDIODRIVER=dummy")

chiaki_bridge_unit_test(chiaki-motion-test motion.cpp)
chiaki_bridge_unit_test(chiaki-microphone-test microphone.cpp)
target_link_libraries(chiaki-microphone-test PRIVATE PkgConfig::LIBCHIAKING_OPUS)
chiaki_bridge_unit_test(chiaki-haptic-rumble-test haptic-rumble.cpp)
chiaki_bridge_unit_test(chiaki-audio-format-test audio-format.cpp)
chiaki_bridge_unit_test(chiaki-bridge-log-test bridge-log.cpp)
chiaki_bridge_unit_test(chiaki-scripted-session-test scripted-session.cpp)
chiaki_bridge_unit_test(chiaki-bridge-facts-test bridge-facts.cpp)
if(LIBCHIAKING_KAKUSAN)
    chiaki_bridge_unit_test(chiaki-kakusan-pair-test kakusan-pair.cpp)
endif()
chiaki_bridge_unit_test(chiaki-secret-residue-test secret-residue.cpp)
chiaki_bridge_unit_test(chiaki-caches-bridge-test caches-bridge.cpp)
chiaki_bridge_unit_test(chiaki-catalog-bridge-test catalog-bridge.cpp)
chiaki_bridge_unit_test(chiaki-http-calls-bridge-test http-calls-bridge.cpp)
chiaki_bridge_unit_test(chiaki-users-bridge-test users-bridge.cpp)
target_compile_definitions(chiaki-bridge-facts-test PRIVATE
    NX_BRIDGE_DIRECTORY="${CMAKE_CURRENT_SOURCE_DIR}/bridge")


add_executable(chiaki-audio-test ../Tests/Native/NativeCoreTests/audio.c bridge/audio.cpp bridge/bridge_log.cpp bridge/runtime.cpp)
target_include_directories(chiaki-audio-test PRIVATE bridge)
target_compile_features(chiaki-audio-test PRIVATE cxx_std_20)
target_link_libraries(chiaki-audio-test PRIVATE libchiaking::libchiaking)
add_test(NAME chiaki-audio-test COMMAND chiaki-audio-test)
