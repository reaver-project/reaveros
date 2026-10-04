file(GLOB sources CONFIGURE_DEPENDS *.cpp)

if (REAVEROS_IS_FREESTANDING)
    set(_library_type STATIC)
else()
    set(_library_type SHARED)
endif()

set(CMAKE_SHARED_LINKER_FLAGS -nostdlib)

add_library(rosestd ${_library_type}
    ${sources}
)

if (NOT REAVEROS_IS_FREESTANDING AND NOT REAVEROS_ENABLE_UNIT_TESTS)
    target_link_libraries(rosestd -Wl,--whole-archive rosert)

    set_target_properties(rosestd
        PROPERTIES
            LINK_DEPENDS ${CMAKE_SYSROOT}/usr/lib/librosert.a
    )
endif()

set_target_properties(rosestd
    PROPERTIES
        COMPILE_FLAGS "-g"
)

set(install_dir ${CMAKE_INSTALL_PREFIX}/usr/lib)

install(TARGETS rosestd
    DESTINATION ${install_dir}
)
