set(install_dir ${CMAKE_INSTALL_PREFIX}/usr/lib)

file(GLOB crt_sources
    CONFIGURE_DEPENDS
    ${REAVEROS_ARCH}/crt*.asm
)

add_library(rosert-crt STATIC
    ${crt_sources}
)

install(TARGETS rosert-crt
    DESTINATION ${install_dir}
)

file(GLOB sources
    CONFIGURE_DEPENDS
    ${REAVEROS_ARCH}/*.asm
    *.cpp
    ${REAVEROS_ARCH}/*.cpp
)

list(REMOVE_ITEM sources ${crt_sources})

add_library(rosert STATIC
    ${sources}
)

target_include_directories(rosert
    SYSTEM PRIVATE ${CMAKE_CURRENT_LIST_DIR}/../../rosestd/include
)

install(TARGETS rosert
    DESTINATION ${install_dir}
)
