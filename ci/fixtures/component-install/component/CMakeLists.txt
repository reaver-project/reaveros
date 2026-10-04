cmake_minimum_required(VERSION 3.31)
cmake_path(GET CMAKE_CURRENT_SOURCE_DIR FILENAME _name)
project(${_name} CXX)

add_executable(${_name} main.cpp)
add_library(${_name}-library SHARED library.cpp)
set_target_properties(${_name}-library PROPERTIES VERSION 1.2 SOVERSION 1)
install(TARGETS ${_name} ${_name}-library
    RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/usr/bin"
    LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}/usr/lib")
install(DIRECTORY files/ DESTINATION "${CMAKE_INSTALL_PREFIX}/usr/include")
install(FILES hosted.h
    DESTINATION "${CMAKE_INSTALL_PREFIX}/../amd64-hosted/usr/include/${_name}")
install(CODE "
    if (EXISTS [==[${CMAKE_CURRENT_SOURCE_DIR}/fail-install]==])
        message(FATAL_ERROR \"Intentional install failure\")
    endif()
")
