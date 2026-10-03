cmake_minimum_required(VERSION 3.31)

# cut a circular dependency caused by our compiler inserting -lrosestd
set(CMAKE_CXX_COMPILER_WORKS 1)

project(reaveros-rosestd CXX)

if (REAVEROS_ENABLE_UNIT_TESTS)
    add_definitions(-D__ROSESTD_TESTING)
endif()

add_subdirectory(include)
add_subdirectory(src)

if (REAVEROS_ENABLE_UNIT_TESTS)
    enable_testing()

    add_subdirectory(test)
endif()
