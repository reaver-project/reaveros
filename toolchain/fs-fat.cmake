reaveros_require_host_tools("dosfstools source configuration" aclocal autoconf automake m4)
# autogen.sh invokes these tools by name. Give it a private directory containing
# exactly the selected executables, also covering nested Autotools invocations.
set(_autotools_path "${CMAKE_CURRENT_BINARY_DIR}/host-autotools")
file(MAKE_DIRECTORY "${_autotools_path}")
foreach (_tool aclocal autoconf automake m4)
    string(TOUPPER "${_tool}" _name)
    file(CREATE_LINK "${REAVEROS_HOST_${_name}}" "${_autotools_path}/${_tool}" SYMBOLIC)
endforeach()

separate_arguments(_cc_options NATIVE_COMMAND "${CMAKE_C_COMPILER_ARG1}")
separate_arguments(_cxx_options NATIVE_COMMAND "${CMAKE_CXX_COMPILER_ARG1}")
_reaveros_shell_command(_autotools_cc ${CMAKE_C_COMPILER_LAUNCHER} "${CMAKE_C_COMPILER}" ${_cc_options})
_reaveros_shell_command(_autotools_cxx ${CMAKE_CXX_COMPILER_LAUNCHER} "${CMAKE_CXX_COMPILER}" ${_cxx_options})
foreach (_language cc cxx)
    set(_wrapper "${CMAKE_CURRENT_BINARY_DIR}/host-${_language}")
    file(CONFIGURE OUTPUT "${_wrapper}"
        CONTENT "#!/bin/sh\nexec ${_autotools_${_language}} \"$@\"\n" @ONLY)
    file(CHMOD "${_wrapper}" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
endforeach()
# Autoconf expands CC/CXX without reparsing embedded quotes. Keep its command
# names simple; each wrapper preserves the compiler and launcher argv.
_reaveros_ep_arguments(_dosfstools_configure _dosfstools_separator
    "${CMAKE_CURRENT_SOURCE_DIR};${REAVEROS_BINARY_DIR};${GIT_EXECUTABLE}"
    "${CMAKE_COMMAND}" -E chdir <SOURCE_DIR>
    "${CMAKE_COMMAND}" -E env "PATH=${_autotools_path}:$ENV{PATH}"
    <SOURCE_DIR>/autogen.sh
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/host-cc" <BINARY_DIR>/reaveros-cc
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/host-cxx" <BINARY_DIR>/reaveros-cxx
    COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}"
    <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
    "CC=reaveros-cc" "CXX=reaveros-cxx")
ExternalProject_Add(toolchain-dosfstools
    GIT_REPOSITORY ${REAVEROS_DOSFSTOOLS_REPO}
    GIT_TAG ${REAVEROS_DOSFSTOOLS_TAG}
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED 1

    PATCH_COMMAND "${GIT_EXECUTABLE}" checkout --detach ${REAVEROS_DOSFSTOOLS_REVISION}

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/dosfstools

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    LIST_SEPARATOR "${_dosfstools_separator}"
    CONFIGURE_COMMAND ${_dosfstools_configure}
    BUILD_COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}" $(MAKE)
    INSTALL_COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}" $(MAKE) install
)
# The executable recipe includes scheduling-only launchers; installation identity
# instead records the compiler and actual configure inputs.
set_property(TARGET toolchain-dosfstools PROPERTY _REAVEROS_CONFIGURATION_INPUTS
    "CC=${CMAKE_C_COMPILER}" "CXX=${CMAKE_CXX_COMPILER}" "prefix=<INSTALL_DIR>"
    ${_reaveros_host_compiler_args}
    "PATH=${_autotools_path}:$ENV{PATH}"
    "aclocal=${REAVEROS_HOST_ACLOCAL}" "autoconf=${REAVEROS_HOST_AUTOCONF}"
    "automake=${REAVEROS_HOST_AUTOMAKE}" "m4=${REAVEROS_HOST_M4}")
reaveros_add_ep_prune_target(toolchain-dosfstools REQUIRED_INSTALLED_OUTPUTS sbin/mkfs.fat)
reaveros_add_ep_fetch_tag_target(toolchain-dosfstools ${REAVEROS_DOSFSTOOLS_REVISION})
reaveros_add_ep_source_identity_step(toolchain-dosfstools ${REAVEROS_DOSFSTOOLS_REVISION}
    DEPENDEES set-to-tag)

reaveros_register_target(toolchain-dosfstools-install toolchain)

_reaveros_ep_arguments(_mtools_configure _mtools_separator
    "${CMAKE_CURRENT_SOURCE_DIR};${REAVEROS_BINARY_DIR}"
    "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/host-cc" <BINARY_DIR>/reaveros-cc
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/host-cxx" <BINARY_DIR>/reaveros-cxx
    COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}"
    <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
    "CC=reaveros-cc" "CXX=reaveros-cxx")
ExternalProject_Add(toolchain-mtools
    URL ${REAVEROS_MTOOLS_DIR}/${REAVEROS_MTOOLS_VER}
    URL_HASH SHA256=${REAVEROS_MTOOLS_SHA256}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    UPDATE_DISCONNECTED 1

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/mtools

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    LIST_SEPARATOR "${_mtools_separator}"
    CONFIGURE_COMMAND ${_mtools_configure}
    BUILD_COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}" $(MAKE)
    INSTALL_COMMAND "${CMAKE_COMMAND}" -E env "PATH=<BINARY_DIR>:$ENV{PATH}" $(MAKE) install
)
set_property(TARGET toolchain-mtools PROPERTY _REAVEROS_CONFIGURATION_INPUTS
    "CC=${CMAKE_C_COMPILER}" "CXX=${CMAKE_CXX_COMPILER}" "prefix=<INSTALL_DIR>"
    ${_reaveros_host_compiler_args})
reaveros_add_ep_prune_target(toolchain-mtools REQUIRED_INSTALLED_OUTPUTS bin/mcopy bin/mformat bin/mmd)
reaveros_add_ep_source_identity_step(toolchain-mtools ${REAVEROS_MTOOLS_SHA256}
    DEPENDEES download update patch)

reaveros_register_target(toolchain-mtools-install toolchain)
