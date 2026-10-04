include_guard(GLOBAL)

# Target identities shared by the superbuild and generated toolchain files.
set(_reaveros_architectures amd64)
set(_reaveros_modes freestanding hosted uefi tests)
set(_reaveros_amd64_processor AMD64)
set(_reaveros_amd64_llvm_backend X86)
set(_reaveros_amd64_freestanding_target x86_64-pc-reaveros-none)
set(_reaveros_amd64_hosted_target x86_64-pc-reaveros-elf)
set(_reaveros_amd64_uefi_target x86_64-windows)
set(_reaveros_amd64_tests_target x86_64-unknown-linux-gnu)
set(_reaveros_freestanding_system ReaverOS)
set(_reaveros_hosted_system ReaverOS)
set(_reaveros_uefi_system ReaverOS)
set(_reaveros_tests_system Linux)

# Language/code-generation requirements of each target environment.
set(_reaveros_no_simd -mno-sse -mno-sse2 -mno-sse3 -mno-sse4 -mno-avx)
set(_reaveros_freestanding_compile_options
    -ffreestanding -fPIC -fno-stack-protector -mno-red-zone ${_reaveros_no_simd})
set(_reaveros_freestanding_cxx_options -fno-rtti -fno-exceptions)
set(_reaveros_freestanding_definitions __ROSE_FREESTANDING)
set(_reaveros_freestanding_executable_link_options -nostartfiles)

set(_reaveros_hosted_compile_options
    -ffreestanding -fPIC -fno-stack-protector -fno-exceptions ${_reaveros_no_simd})
set(_reaveros_hosted_cxx_options)
set(_reaveros_hosted_definitions)
set(_reaveros_hosted_executable_link_options)

set(_reaveros_uefi_compile_options
    -ffreestanding -fno-stack-protector -mno-red-zone -mno-stack-arg-probe ${_reaveros_no_simd})
set(_reaveros_uefi_cxx_options -fno-rtti -fno-exceptions)
set(_reaveros_uefi_definitions __ROSE_FREESTANDING __ROSE_UEFI)
set(_reaveros_uefi_executable_link_options
    -nostartfiles -nostdlib -fuse-ld=lld-link
    LINKER:-subsystem:efi_application LINKER:-entry:efi_main)

set(_reaveros_tests_compile_options)
set(_reaveros_tests_cxx_options -stdlib=libc++)
set(_reaveros_tests_definitions)
set(_reaveros_tests_executable_link_options)
