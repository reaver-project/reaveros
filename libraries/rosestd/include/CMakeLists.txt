set(includes
    climits
    cstddef
    cstdint
    cstring
    cwchar

    algorithm
    atomic
    charconv
    chrono
    compare
    concepts
    format
    iterator
    memory
    mutex
    new
    optional
    ratio
    shared_mutex
    string_view
    system_error
    type_traits
    utility
    variant
    version

    __config
    __char_traits
)

if (NOT REAVEROS_ENABLE_UNIT_TESTS)
    if (NOT REAVEROS_IS_UEFI)
        set(install_dir usr/include/rosestd/v0)
    else()
        set(install_dir usr/include)
    endif()
else()
    set(install_dir usr/include/rosestd)
endif()

install(FILES ${includes}
    DESTINATION ${install_dir}
)
