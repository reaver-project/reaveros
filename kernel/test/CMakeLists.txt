add_custom_target(build-tests)

add_compile_definitions(REAVEROS_TESTING)

file(GLOB_RECURSE test_files RELATIVE "${CMAKE_CURRENT_LIST_DIR}" CONFIGURE_DEPENDS
    *.test.cpp
)

foreach (file IN LISTS test_files)
    string(REPLACE "/" "--" file_escaped ${file})
    string(REGEX REPLACE ".test.cpp$" ".test" exe_name ${file_escaped})
    string(REGEX REPLACE ".test.cpp$" "" test_name ${file})

    add_executable(${exe_name} "${file}")
    target_compile_options(${exe_name} PRIVATE -UNDEBUG)
    add_dependencies(build-tests ${exe_name})

    add_test(${test_name} ${exe_name})
endforeach()
