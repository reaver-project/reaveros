include_guard(GLOBAL)

function(_reaveros_ep_step_stamp _output _project _step)
    if (NOT CMAKE_GENERATOR STREQUAL "Unix Makefiles")
        message(FATAL_ERROR "ExternalProject stamp handling requires Unix Makefiles.")
    endif()
    ExternalProject_Get_Property(${_project} STAMP_DIR)
    if (_step STREQUAL "complete")
        set(_stamp "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/${_project}-complete")
    else()
        set(_stamp "${STAMP_DIR}/${_project}-${_step}")
    endif()
    set(${_output} "${_stamp}" PARENT_SCOPE)
endfunction()

# Stamp replay is tied to the single-config Unix Makefiles generator. Keep
# these assumptions together when updating the pinned CMake version.
function(_reaveros_ep_legacy_prune_commands _output external_project source_step
        prune_SOURCE_STEP_AFTER_PATCH prune_REMOVE_DOWNLOADED_ARCHIVE)
    ExternalProject_Get_Property(${external_project} STAMP_DIR UPDATE_DISCONNECTED)
    # The pruned source checkout cannot run apply-patches again.
    set(_commands
        COMMAND rm -rf <SOURCE_DIR> <BINARY_DIR>
        COMMAND rm -rf ${STAMP_DIR}/${external_project}-gitclone-lastrun.txt
    )
    if (NOT prune_SOURCE_STEP_AFTER_PATCH)
        list(APPEND _commands COMMAND touch ${STAMP_DIR}/${external_project}-${source_step})
    endif()
    if (UPDATE_DISCONNECTED)
        list(APPEND _commands
            COMMAND touch ${STAMP_DIR}/${external_project}-update_disconnected
            COMMAND touch ${STAMP_DIR}/${external_project}-patch_disconnected
        )
    endif()
    list(APPEND _commands
        COMMAND touch ${STAMP_DIR}/${external_project}-skip-update
        COMMAND touch ${STAMP_DIR}/${external_project}-update
        COMMAND touch ${STAMP_DIR}/${external_project}-patch
    )
    if (prune_SOURCE_STEP_AFTER_PATCH)
        list(APPEND _commands COMMAND touch ${STAMP_DIR}/${external_project}-${source_step})
    endif()
    list(APPEND _commands
        COMMAND touch ${STAMP_DIR}/${external_project}-apply-patches
        COMMAND touch ${STAMP_DIR}/${external_project}-invalidate-build
        COMMAND touch ${STAMP_DIR}/${external_project}-configure
        COMMAND touch ${STAMP_DIR}/${external_project}-build
        COMMAND touch ${STAMP_DIR}/${external_project}-install
    )
    if (prune_REMOVE_DOWNLOADED_ARCHIVE)
        # Validation images must keep the download stamp even after dropping
        # the archive, or ordinary targets will rebuild the toolchain.
        list(APPEND _commands
            COMMAND rm -f <DOWNLOADED_FILE>
        )
    endif()

    set(${_output} "${_commands}" PARENT_SCOPE)
endfunction()

function(_reaveros_ep_refresh_stamps_after_build external_project)
    ExternalProject_Get_Property(${external_project} STAMP_DIR)
    add_custom_command(TARGET ${external_project} POST_BUILD
        COMMAND touch ${STAMP_DIR}/${external_project}-set-to-tag
        COMMAND touch ${STAMP_DIR}/${external_project}-invalidate-build
        COMMAND touch ${STAMP_DIR}/${external_project}-skip-update
        COMMAND touch ${STAMP_DIR}/${external_project}-patch
        COMMAND touch ${STAMP_DIR}/${external_project}-apply-patches
        COMMAND touch ${STAMP_DIR}/${external_project}-configure
        COMMAND touch ${STAMP_DIR}/${external_project}-build
        COMMAND touch ${STAMP_DIR}/${external_project}-install
        COMMAND rm -rf ${STAMP_DIR}/${external_project}-prune
        VERBATIM
    )
endfunction()

function(_reaveros_ep_configuration_identity _output _project)
    get_property(_args TARGET ${_project} PROPERTY _EP_CMAKE_ARGS)
    get_property(_configure TARGET ${_project} PROPERTY _EP_CONFIGURE_COMMAND)
    list(FILTER _args EXCLUDE REGEX "^-D(CMAKE_(C|CXX)_COMPILER_LAUNCHER|LLVM_PARALLEL_LINK_JOBS)=")
    string(SHA256 _identity "${_args}\n${_configure}")
    set(${_output} "${_identity}" PARENT_SCOPE)
endfunction()

function(_reaveros_ep_configure_input _output _project)
    ExternalProject_Get_Property(${_project} TMP_DIR)
    set(${_output} "${TMP_DIR}/${_project}-cfgcmd.txt" PARENT_SCOPE)
endfunction()

function(_reaveros_ep_prune_steps _output _source_step _after_patch _disconnected)
    set(_steps "")
    if (NOT _after_patch)
        list(APPEND _steps "${_source_step}")
    endif()
    if (_disconnected)
        list(APPEND _steps update_disconnected patch_disconnected)
    endif()
    list(APPEND _steps skip-update update patch)
    if (_after_patch)
        list(APPEND _steps "${_source_step}")
    endif()
    list(APPEND _steps apply-patches invalidate-build configure build install)
    set(${_output} "${_steps}" PARENT_SCOPE)
endfunction()

function(_reaveros_add_ep_file_dependencies external_project step)
    # Add_StepDependencies also adds target dependencies, so it cannot accept
    # files once the step has its own target. Make uses these single-config stamps.
    _reaveros_ep_step_stamp(_stamp "${external_project}" "${step}")
    add_custom_command(APPEND
        OUTPUT "${_stamp}"
        DEPENDS ${ARGN}
    )
endfunction()
