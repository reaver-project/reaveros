cmake_minimum_required(VERSION 3.31)

set(CMAKE_CXX_COMPILER_WORKS 1)

# cut a circular dependency caused by our compiler inserting -lrosestd -lrose-crt
set(CMAKE_CXX_COMPILER_WORKS 1)
project(reaveros-rosert ASM CXX)

add_subdirectory(include)
add_subdirectory(src)
