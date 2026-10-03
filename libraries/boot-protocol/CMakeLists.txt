cmake_minimum_required(VERSION 3.31)

project(reaveros-boot-protocol CXX)

add_subdirectory(include)

if (REAVEROS_ENABLE_UNIT_TESTS)
    add_custom_target(build-tests)
endif()
