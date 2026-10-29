# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(drinphone LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "drinphone")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# liblinphone (linphone-sdk-win64 ufficiale) accanto all'exe: DLL, dati del core
# (grammatiche belr, CA root, suonerie) e plugin mediastreamer. WASAPI è un plugin:
# senza, il core non vede schede audio. webrtc = cancellazione eco. libmsopenh264 è
# il ponte verso H264: importa openh264.dll di Cisco, che NON si ridistribuisce e
# l'app scarica a richiesta (DECISIONS "Videochiamate"); senza, il plugin non si
# carica e resta VP8. SDK scaricato da tool/fetch_linphone_sdk.ps1.
set(LINPHONE_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/linphone-sdk/win64")
if(NOT EXISTS "${LINPHONE_SDK_DIR}/bin/liblinphone.dll")
  message(FATAL_ERROR "linphone-sdk mancante: esegui powershell -File tool/fetch_linphone_sdk.ps1")
endif()
file(GLOB LINPHONE_DLLS "${LINPHONE_SDK_DIR}/bin/*.dll")
list(FILTER LINPHONE_DLLS EXCLUDE REGEX "tester|bcunit|CsWrapper")
install(FILES ${LINPHONE_DLLS} DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
foreach(share_dir belr linphone sounds)
  install(DIRECTORY "${LINPHONE_SDK_DIR}/share/${share_dir}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/linphone/share" COMPONENT Runtime)
endforeach()
install(FILES
    "${LINPHONE_SDK_DIR}/lib/mediastreamer/plugins/libmswasapi.dll"
    "${LINPHONE_SDK_DIR}/lib/mediastreamer/plugins/libmswebrtc.dll"
    "${LINPHONE_SDK_DIR}/lib/mediastreamer/plugins/libmsopenh264.dll"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/linphone/plugins" COMPONENT Runtime)

# ANGLE (libEGL/libGLESv2) accanto all'exe: senza, il video non si vede (MSOGL).
# Scaricato e verificato da tool/fetch_angle.ps1; se manca, solo avviso.
set(ANGLE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/angle")
if(EXISTS "${ANGLE_DIR}/libEGL.dll" AND EXISTS "${ANGLE_DIR}/libGLESv2.dll")
  install(FILES "${ANGLE_DIR}/libEGL.dll" "${ANGLE_DIR}/libGLESv2.dll"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
else()
  message(WARNING "ANGLE mancante: video non visualizzato. Esegui powershell -File tool/fetch_angle.ps1")
endif()
