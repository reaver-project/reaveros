cmake_minimum_required(VERSION 3.31)
project(example C)
if (EXISTS "${TEST_CONTROL}/fail-configure")
    message(FATAL_ERROR "Intentional configure failure")
endif()
add_executable(example main.c)
target_compile_definitions(example PRIVATE TEST_VALUE=${TEST_VALUE})
add_custom_target(check-build ALL
    COMMAND "${CMAKE_COMMAND}" "-DTEST_CONTROL=${TEST_CONTROL}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/check-build.cmake")
install(CODE "if (EXISTS [==[${TEST_CONTROL}/fail-install]==])\nmessage(FATAL_ERROR \"Intentional install failure\")\nendif()")
install(TARGETS example RUNTIME DESTINATION bin)
