set(REAVEROS_LLVM_PARALLEL_LINK_JOBS 8 CACHE STRING "Sets the limit for parallel link jobs of LLVM.")

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

set(_fakeroot "--sysroot='${CMAKE_CURRENT_SOURCE_DIR}/llvm/fakeroot'")
set(_llvm_backends)

foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
    list(APPEND _llvm_backends "${_reaveros_${architecture}_llvm_backend}")
    set(_processor ${_reaveros_${architecture}_processor})
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
                -D${_llvm_runtime}_${_target}_CMAKE_SYSTEM_NAME=${_reaveros_${mode}_system}
                -D${_llvm_runtime}_${_target}_CMAKE_SYSTEM_PROCESSOR=${_processor}
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
list(REMOVE_DUPLICATES _llvm_backends)
string(JOIN "|" _llvm_backends ${_llvm_backends})

set(patch_files
    ${CMAKE_CURRENT_LIST_DIR}/llvm/patches/000-reaveros-support-with-less-plt.patch
)
reaveros_patch_dependency(
    patch_dependency toolchain-llvm
    ${REAVEROS_LLVM_REVISION}-${REAVEROS_LLVM_SOURCE_SHA256} ${patch_files}
    "${REAVEROS_SOURCE_DIR}/toolchain/hydrate-git-archive"
)

string(REGEX REPLACE "^llvmorg-" "" _llvm_source_version "${REAVEROS_LLVM_TAG}")
ExternalProject_Add(toolchain-llvm
    URL ${REAVEROS_LLVM_REPO}/releases/download/${REAVEROS_LLVM_TAG}/llvm-project-${_llvm_source_version}.src.tar.xz
    URL_HASH SHA256=${REAVEROS_LLVM_SOURCE_SHA256}
    DOWNLOAD_NO_EXTRACT TRUE
    TLS_VERIFY TRUE
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
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
        -DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}
        -DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}
        -DCMAKE_BUILD_TYPE=Release
        -Wno-dev
        -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
        -DLLVM_TARGETS_TO_BUILD=${_llvm_backends}
        -DLLVM_ENABLE_PROJECTS=clang|lld
        -DLLVM_ENABLE_RUNTIMES=libunwind|libcxx|libcxxabi
        -DLLVM_RUNTIME_TARGETS=${_runtime_targets}
        -DLLVM_BUILTIN_TARGETS=${_runtime_targets}
        "${_runtime_flags}"
        -DLLVM_PARALLEL_LINK_JOBS=${REAVEROS_LLVM_PARALLEL_LINK_JOBS}
        -DLLVM_INCLUDE_TESTS=OFF
        -DLLVM_INCLUDE_EXAMPLES=OFF
)
_reaveros_add_ep_file_dependencies(toolchain-llvm download ${patch_dependency})
ExternalProject_Add_Step(toolchain-llvm
    hydrate-source
    COMMAND "${CMAKE_COMMAND}" -E env "GIT_EXECUTABLE=${GIT_EXECUTABLE}"
        bash "${REAVEROS_SOURCE_DIR}/toolchain/hydrate-git-archive"
        <SOURCE_DIR> ${REAVEROS_LLVM_REPO} ${REAVEROS_LLVM_TAG}
        ${REAVEROS_LLVM_REVISION} <DOWNLOADED_FILE>
    DEPENDEES download update patch
    DEPENDERS configure
    DEPENDS ${patch_dependency}
)
reaveros_add_ep_source_identity_step(toolchain-llvm
    ${REAVEROS_LLVM_REVISION}:${REAVEROS_LLVM_SOURCE_SHA256}
    DEPENDEES hydrate-source)
ExternalProject_Add_Step(toolchain-llvm
    apply-patches
    COMMAND "${GIT_EXECUTABLE}" reset --hard
    COMMAND "${GIT_EXECUTABLE}" clean -fxd
    COMMAND "${GIT_EXECUTABLE}" checkout --detach ${REAVEROS_LLVM_REVISION}
    COMMAND "${GIT_EXECUTABLE}" apply ${patch_files}
    DEPENDEES hydrate-source
    DEPENDERS configure
    WORKING_DIRECTORY <SOURCE_DIR>
)
string(REGEX REPLACE "^llvmorg-([0-9]+).*" "\\1" _llvm_version "${REAVEROS_LLVM_TAG}")
set(_required_llvm_outputs bin/clang bin/clang++ bin/ld.lld bin/lld-link
    bin/llvm-ar bin/llvm-ranlib bin/llvm-readelf bin/llvm-readobj bin/llvm-objcopy bin/llvm-nm
    "lib/clang/${_llvm_version}/include/stddef.h")
foreach (_architecture IN LISTS REAVEROS_ARCHITECTURES)
    foreach (_mode freestanding hosted)
        list(APPEND _required_llvm_outputs
            "lib/clang/${_llvm_version}/lib/${_reaveros_${_architecture}_${_mode}_target}/libclang_rt.builtins.a")
    endforeach()
    if (REAVEROS_ENABLE_UNIT_TESTS)
        list(APPEND _required_llvm_outputs
            "include/c++/v1/cstddef"
            "include/${_reaveros_${_architecture}_tests_target}/c++/v1/__config_site")
        foreach (_library libc++.so libc++abi.so libunwind.so)
            list(APPEND _required_llvm_outputs "lib/${_reaveros_${_architecture}_tests_target}/${_library}")
        endforeach()
    endif()
endforeach()
reaveros_add_ep_prune_target(toolchain-llvm
    SOURCE_STEP hydrate-source
    SOURCE_STEP_AFTER_PATCH
    REMOVE_DOWNLOADED_ARCHIVE
    REQUIRED_INSTALLED_OUTPUTS ${_required_llvm_outputs}
)

# install compiler-rt to the appropriate sysroots
string(REGEX REPLACE "llvmorg-(([0-9]+)\.[0-9]+\.[0-9])+(-.*)?" "\\2" _llvm_version "${REAVEROS_LLVM_TAG}")
foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
    foreach (mode IN ITEMS freestanding hosted)
        set(_sub_path "${_llvm_version}/lib/${_reaveros_${architecture}_${mode}_target}")
        set(_builtin_lib "${REAVEROS_BINARY_DIR}/install/toolchain/llvm/lib/clang/${_sub_path}/libclang_rt.builtins.a")
        set(_destination "${REAVEROS_BINARY_DIR}/install/sysroots/${architecture}-${mode}/usr/lib")

        # The main ExternalProject target depends on its install step target.
        # Keep one producer, which also repairs copies in deleted sysroots.
        add_custom_command(TARGET toolchain-llvm-install POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${_destination}"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${_builtin_lib}" "${_destination}/libclang_rt.builtins.a"
            BYPRODUCTS "${_destination}/libclang_rt.builtins.a"
            VERBATIM
        )
    endforeach()
endforeach()

reaveros_register_target(toolchain-llvm-install toolchain)
