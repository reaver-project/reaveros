cmake_minimum_required(VERSION 3.31)

project(reaveros-rosestd CXX)

if (REAVEROS_ENABLE_UNIT_TESTS)
    add_compile_definitions(__ROSESTD_TESTING)
endif()

add_subdirectory(include)
add_subdirectory(src)

if (REAVEROS_ENABLE_UNIT_TESTS)
    enable_testing()

    add_subdirectory(test)
endif()
