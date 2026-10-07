cmake_minimum_required(VERSION 3.31)
project(lifecycle-guard-test LANGUAGES NONE)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

foreach (project one two)
    foreach (operation build prune)
        add_custom_target(${project}-${operation}
            COMMAND "${Python3_EXECUTABLE}" "${TEST_REPOSITORY}/toolchain/guard-lifecycle"
                "${CMAKE_BINARY_DIR}" toolchain-${project} ${operation} "${CMAKE_MAKE_PROGRAM}"
            COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/worker.py"
                "${CMAKE_BINARY_DIR}" ${project} ${operation}
            VERBATIM
        )
    endforeach()
endforeach()
