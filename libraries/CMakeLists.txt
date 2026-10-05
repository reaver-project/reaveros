set(libraries
    rosert
    rosestd

    boot-protocol

    archive
    elf
)

foreach (library IN LISTS libraries)
    reaveros_include_component("${library}" PREFIX library TAGS libraries)
endforeach()
