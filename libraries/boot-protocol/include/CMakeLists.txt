set(includes
    boot-arguments.h
    boot-constants.h
    boot-memmap.h
    boot-video.h
)

install(FILES ${includes}
    DESTINATION usr/include
)
