file(GLOB sources CONFIGURE_DEPENDS *.cpp)

if (REAVEROS_IS_FREESTANDING)
    set(_library_type STATIC)
else()
    set(_library_type SHARED)
endif()

add_library(archive ${_library_type}
    ${sources}
)
target_compile_options(archive PRIVATE -g)
if (_library_type STREQUAL "SHARED")
    reaveros_require_linker_dependencies(archive CXX)
endif()

install(TARGETS archive
    DESTINATION usr/lib
)
