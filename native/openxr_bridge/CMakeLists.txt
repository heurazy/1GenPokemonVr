cmake_minimum_required(VERSION 3.21)
project(gen1openxr LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(OpenXR CONFIG REQUIRED)

add_library(gen1openxr SHARED gen1openxr.cpp)
target_compile_definitions(gen1openxr PRIVATE
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  XR_USE_PLATFORM_WIN32
  XR_USE_GRAPHICS_API_OPENGL
)
target_link_libraries(gen1openxr PRIVATE OpenXR::openxr_loader opengl32)

set_target_properties(gen1openxr PROPERTIES
  OUTPUT_NAME "gen1openxr"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/bin"
  RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/bin"
)
