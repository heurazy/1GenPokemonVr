cmake_minimum_required(VERSION 3.21)
project(gen1openxr_quest LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED OPENXR_AAR_ROOT)
  message(FATAL_ERROR "OPENXR_AAR_ROOT must point to the extracted Khronos OpenXR loader AAR")
endif()

add_library(openxr_loader SHARED IMPORTED)
set_target_properties(openxr_loader PROPERTIES
  IMPORTED_LOCATION "${OPENXR_AAR_ROOT}/jni/arm64-v8a/libopenxr_loader.so")

add_library(gen1openxr SHARED ../gen1openxr.cpp)
target_include_directories(gen1openxr PRIVATE
  "${OPENXR_AAR_ROOT}/prefab/modules/headers/include")
target_link_libraries(gen1openxr PRIVATE
  openxr_loader EGL GLESv3 android log dl)

set_target_properties(gen1openxr PROPERTIES OUTPUT_NAME "gen1openxr")
