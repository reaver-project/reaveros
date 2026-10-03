cmake_minimum_required(VERSION 3.31)
project(reaveros-thorn CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_EXTENSIONS OFF)

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
