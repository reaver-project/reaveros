file(GLOB sources CONFIGURE_DEPENDS *.cpp)

if (REAVEROS_IS_FREESTANDING)
    set(_library_type STATIC)
else()
    set(_library_type SHARED)
endif()

add_library(rosestd ${_library_type}
    ${sources}
)
target_compile_options(rosestd PRIVATE -g)
target_link_options(rosestd PRIVATE -nostdlib)

if (NOT REAVEROS_IS_FREESTANDING AND NOT REAVEROS_ENABLE_UNIT_TESTS)
    # ReaverOS does not define CMake's WHOLE_ARCHIVE library feature. Bound
    # the linker state explicitly so later libraries retain normal behavior.
    target_link_libraries(rosestd PRIVATE -Wl,--whole-archive rosert -Wl,--no-whole-archive)
endif()

if (_library_type STREQUAL "SHARED")
    reaveros_require_linker_dependencies(rosestd CXX)
endif()

install(TARGETS rosestd
    DESTINATION usr/lib
)
