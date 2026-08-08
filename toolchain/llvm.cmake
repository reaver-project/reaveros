set(REAVEROS_LLVM_PARALLEL_LINK_JOBS 8 CACHE STRING "Sets the limit for parallel link jobs of LLVM.")

set(_reaveros_amd64_freestanding_target x86_64-pc-reaveros-none)
set(_reaveros_amd64_freestanding_flags
    COMPILER_RT_BUILD_BUILTINS=ON
    COMPILER_RT_BUILD_LIBFUZZER=OFF
    COMPILER_RT_BUILD_MEMPROF=OFF
    COMPILER_RT_BUILD_PROFILE=OFF
    COMPILER_RT_BUILD_SANITIZERS=OFF
    COMPILER_RT_BUILD_XRAY=OFF
    COMPILER_RT_DEFAULT_TARGET_ONLY=ON
    COMPILER_RT_BAREMETAL_BUILD=ON
)
set(_reaveros_amd64_freestanding_extra_cc_flags
    "-fno-rtti -fno-exceptions -mno-red-zone -fno-stack-protector"
)

set(_reaveros_amd64_hosted_target x86_64-pc-reaveros-elf)
set(_reaveros_amd64_hosted_flags
    COMPILER_RT_BUILD_BUILTINS=ON
    COMPILER_RT_BUILD_LIBFUZZER=OFF
    COMPILER_RT_BUILD_MEMPROF=OFF
    COMPILER_RT_BUILD_PROFILE=OFF
    COMPILER_RT_BUILD_SANITIZERS=OFF
    COMPILER_RT_BUILD_XRAY=OFF
    COMPILER_RT_DEFAULT_TARGET_ONLY=ON
    COMPILER_RT_BAREMETAL_BUILD=ON
)

set(_runtime_targets default)
if (REAVEROS_ENABLE_UNIT_TESTS)
    set(_runtime_flags
        -DRUNTIMES_default_LLVM_ENABLE_RUNTIMES=compiler-rt|libunwind|libcxx|libcxxabi
        -DRUNTIMES_default_COMPILER_RT_BUILD_BUILTINS=ON
        -DRUNTIMES_default_COMPILER_RT_BUILD_LIBFUZZER=OFF
        -DRUNTIMES_default_COMPILER_RT_BUILD_MEMPROF=OFF
        -DRUNTIMES_default_COMPILER_RT_BUILD_PROFILE=OFF
        -DRUNTIMES_default_COMPILER_RT_BUILD_SANITIZERS=OFF
        -DRUNTIMES_default_COMPILER_RT_BUILD_XRAY=OFF
        -DRUNTIMES_default_COMPILER_RT_DEFAULT_TARGET_ONLY=ON
    )
else()
    set(_runtime_targets)
    set(_runtime_flags)
endif()

set(_fakeroot "--sysroot=${CMAKE_CURRENT_SOURCE_DIR}/llvm/fakeroot")

foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
    foreach (mode IN ITEMS freestanding hosted)
        set(_target ${_reaveros_${architecture}_${mode}_target})
        set(_cc_flags ${_reaveros_${architecture}_${mode}_extra_cc_flags})
        if ("${_runtime_targets}" STREQUAL "")
            set(_runtime_targets ${_target})
        else()
            string(APPEND _runtime_targets
                |${_target}
            )
        endif()
        foreach (_llvm_runtime IN ITEMS BUILTINS RUNTIMES)
            list(APPEND _runtime_flags
                -D${_llvm_runtime}_${_target}_LLVM_ENABLE_RUNTIMES=compiler-rt
                -D${_llvm_runtime}_${_target}_CMAKE_SYSTEM_NAME=ReaverOS
                -D${_llvm_runtime}_${_target}_CMAKE_SYSTEM_PROCESSOR=${_arch}
                -D${_llvm_runtime}_${_target}_CMAKE_BUILD_TYPE=RelWithDebInfo
                "-D${_llvm_runtime}_${_target}_CMAKE_ASM_FLAGS=-nodefaultlibs -nostartfiles ${_fakeroot} ${_cc_flags}"
                "-D${_llvm_runtime}_${_target}_CMAKE_C_FLAGS=-nodefaultlibs -nostartfiles ${_fakeroot} ${_cc_flags}"
                "-D${_llvm_runtime}_${_target}_CMAKE_CXX_FLAGS=-nodefaultlibs -nostartfiles ${_fakeroot} ${_cc_flags}"
            )
            foreach (_flag IN LISTS _reaveros_${architecture}_${mode}_flags)
                list(APPEND _runtime_flags -D${_llvm_runtime}_${_target}_${_flag})
            endforeach()
        endforeach()
    endforeach()
endforeach()

set(patch_files
    ${CMAKE_CURRENT_LIST_DIR}/llvm/patches/000-reaveros-support-with-less-plt.patch
)

ExternalProject_Add(toolchain-llvm
    GIT_REPOSITORY ${REAVEROS_LLVM_REPO}
    GIT_TAG ${REAVEROS_LLVM_REVISION}
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED 1

    STEP_TARGETS install

    DEPENDS toolchain-cmake-install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/llvm

    SOURCE_SUBDIR llvm
    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    LIST_SEPARATOR |

    PATCH_COMMAND ""

    CMAKE_COMMAND ${REAVEROS_CMAKE}
    CMAKE_ARGS
        -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
        -DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}
        -DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}
        -DCMAKE_BUILD_TYPE=Release
        -Wno-dev
        -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
        -DLLVM_TARGETS_TO_BUILD=X86
        -DLLVM_ENABLE_PROJECTS=clang|lld
        -DLLVM_ENABLE_RUNTIMES=libunwind|libcxx|libcxxabi
        -DLLVM_RUNTIME_TARGETS=${_runtime_targets}
        -DLLVM_BUILTIN_TARGETS=${_runtime_targets}
        "${_runtime_flags}"
        -DLLVM_PARALLEL_LINK_JOBS=${REAVEROS_LLVM_PARALLEL_LINK_JOBS}
        -DLLVM_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_EXAMPLES=OFF
)
ExternalProject_Add_Step(toolchain-llvm
    apply-patches
    COMMAND git reset --hard
    COMMAND git clean -fxd
    COMMAND git apply ${patch_files}
    DEPENDEES set-to-tag
    DEPENDERS configure
    DEPENDS ${patch_files}
    WORKING_DIRECTORY <SOURCE_DIR>
)
reaveros_add_ep_prune_target(toolchain-llvm)
reaveros_add_ep_fetch_tag_target(toolchain-llvm)

# install compiler-rt to the appropriate sysroots
string(REGEX REPLACE "llvmorg-(([0-9]+)\.[0-9]+\.[0-9])+(-.*)?" "\\2" _llvm_version "${REAVEROS_LLVM_TAG}")
ExternalProject_Get_Property(toolchain-llvm BINARY_DIR)

foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
    foreach (mode IN ITEMS freestanding hosted)
        set(_sub_path "${_llvm_version}/lib/${_reaveros_${architecture}_${mode}_target}")
        set(_builtin_lib "${REAVEROS_BINARY_DIR}/install/toolchain/llvm/lib/clang/${_sub_path}/libclang_rt.builtins.a")
        set(_destination "${REAVEROS_BINARY_DIR}/install/sysroots/${architecture}-${mode}/usr/lib")

        add_custom_command(TARGET toolchain-llvm POST_BUILD
            COMMAND mkdir -p ${_destination}
            COMMAND cp ${_builtin_lib} ${_destination}
        )
        add_custom_command(TARGET toolchain-llvm-install POST_BUILD
            COMMAND mkdir -p ${_destination}
            COMMAND cp ${_builtin_lib} ${_destination}
        )
    endforeach()
endforeach()

reaveros_register_target(toolchain-llvm-install toolchain)
