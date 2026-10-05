cmake_minimum_required(VERSION 3.31)

project(reaveros-service-logger CXX)

add_executable(logger
    main.cpp
    ../../../kernel/bootinit/print.cpp
    # yes the above is a hack, however, this "first logger" service *is* interacting with the kernel beyond public APIs
    # so it is somewhat similar to bootinit in that respect
)

set_target_properties(logger
    PROPERTIES
        SUFFIX ".srv"
)
target_compile_options(logger PRIVATE -g -fno-rtti)
reaveros_require_linker_dependencies(logger CXX)

install(TARGETS logger
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)
