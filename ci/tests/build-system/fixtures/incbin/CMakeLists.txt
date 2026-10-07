cmake_minimum_required(VERSION 3.31)
project(incbin-test CXX ASM)

# Native compiler drivers need this for the production .asm extension.
set(CMAKE_ASM_FLAGS "-x assembler")
add_subdirectory(bootinit)
add_subdirectory(vdso)
add_executable(incbin-consumer consumer.cpp)
target_link_libraries(incbin-consumer bootinit-incbin vdso-incbin)
