cmake_minimum_required(VERSION 3.31)
project(reaveros-thorn CXX)

add_executable(thorn
    main.cpp
    context.cpp
    parser.cpp
    generator.cpp
)

include(GNUInstallDirs)

install(TARGETS thorn
    DESTINATION ${CMAKE_INSTALL_BINDIR}
)
