include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/host_tools.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/external_project_make.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/toolchain_contracts.cmake")

function(reaveros_file_dependency output_file dependency_name identity)
    # Checkout mtimes differ between CI jobs even when the input contents do not.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${ARGN})
    set(_inputs "revision:${identity}\n")
    foreach (_input_file IN LISTS ARGN)
        file(SHA256 "${_input_file}" _input_hash)
        string(APPEND _inputs "${_input_file}:${_input_hash}\n")
    endforeach()
    string(SHA256 _inputs_hash "${_inputs}")

    set(_dependency "${REAVEROS_BINARY_DIR}/toolchain/${dependency_name}")
    file(CONFIGURE OUTPUT "${_dependency}" CONTENT "${_inputs_hash}" @ONLY)

    set(${output_file} "${_dependency}" PARENT_SCOPE)
endfunction()

function(reaveros_patch_dependency output_file external_project source_revision)
    reaveros_file_dependency(_dependency "${external_project}-patch-inputs"
        "${source_revision}" ${ARGN})
    set(${output_file} "${_dependency}" PARENT_SCOPE)
endfunction()

function(reaveros_add_ep_prune_target external_project)
    cmake_parse_arguments(PARSE_ARGV 1 prune "REMOVE_DOWNLOADED_ARCHIVE;SOURCE_STEP_AFTER_PATCH"
        "SOURCE_STEP" "REQUIRED_INSTALLED_OUTPUTS")
    if (prune_UNPARSED_ARGUMENTS OR prune_KEYWORDS_MISSING_VALUES)
        message(FATAL_ERROR "Invalid prune options for '${external_project}': ${prune_UNPARSED_ARGUMENTS} ${prune_KEYWORDS_MISSING_VALUES}")
    endif()
    ExternalProject_Get_Property(${external_project} STAMP_DIR UPDATE_DISCONNECTED)
    if (prune_SOURCE_STEP)
        set(source_step "${prune_SOURCE_STEP}")
    else()
        set(source_step set-to-tag)
    endif()

    if (prune_REQUIRED_INSTALLED_OUTPUTS)
        set_property(TARGET ${external_project} PROPERTY _REAVEROS_REQUIRED_OUTPUTS "${prune_REQUIRED_INSTALLED_OUTPUTS}")
        set_property(TARGET ${external_project} PROPERTY _REAVEROS_PRUNE_SOURCE_STEP "${source_step}")
        set_property(TARGET ${external_project} PROPERTY _REAVEROS_PRUNE_AFTER_PATCH "${prune_SOURCE_STEP_AFTER_PATCH}")
        set_property(TARGET ${external_project} PROPERTY _REAVEROS_PRUNE_ARCHIVE "${prune_REMOVE_DOWNLOADED_ARCHIVE}")
        set_property(DIRECTORY APPEND PROPERTY _REAVEROS_LIFECYCLE_PROJECTS "${external_project}")
        get_property(_scheduled DIRECTORY PROPERTY _REAVEROS_LIFECYCLE_SCHEDULED)
        if (NOT _scheduled)
            set_property(DIRECTORY PROPERTY _REAVEROS_LIFECYCLE_SCHEDULED TRUE)
            cmake_language(DEFER CALL _reaveros_finalize_toolchain_lifecycles)
        endif()
        reaveros_require_host_python()
        set(_commands COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../toolchain/installed-state"
            prune "${REAVEROS_BINARY_DIR}/toolchain/${external_project}-lifecycle.json")
    else()
        _reaveros_ep_legacy_prune_commands(_commands "${external_project}" "${source_step}"
            "${prune_SOURCE_STEP_AFTER_PATCH}" "${prune_REMOVE_DOWNLOADED_ARCHIVE}")
    endif()

    ExternalProject_Add_Step(${external_project}
        prune
        ${_commands}
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
    )
    ExternalProject_Add_StepTargets(${external_project} prune)

    add_dependencies(all-toolchain-prune
        ${external_project}-prune
    )
endfunction()

function(reaveros_add_ep_source_identity_step external_project identity)
    reaveros_require_host_tools("Upstream source validation" bash)
    set_property(TARGET ${external_project} PROPERTY _REAVEROS_SOURCE_ID "${identity}")
    cmake_parse_arguments(PARSE_ARGV 2 source "" "" "DEPENDEES")
    if (source_UNPARSED_ARGUMENTS OR source_KEYWORDS_MISSING_VALUES OR NOT source_DEPENDEES)
        message(FATAL_ERROR "Invalid source identity step for ${external_project}")
    endif()

    set(dependency "${REAVEROS_BINARY_DIR}/toolchain/${external_project}-source-inputs")
    file(CONFIGURE OUTPUT "${dependency}" CONTENT "${identity}\n" @ONLY)

    reaveros_file_dependency(helper_dependency "${external_project}-invalidation-inputs"
        invalidate-stale-build "${REAVEROS_SOURCE_DIR}/toolchain/invalidate-stale-build")

    # A changed helper must be able to restore pruned sources before configure.
    _reaveros_add_ep_file_dependencies(${external_project} download ${helper_dependency})
    foreach (source_step IN LISTS source_DEPENDEES)
        if (NOT source_step STREQUAL "download")
            _reaveros_add_ep_file_dependencies(${external_project} ${source_step} ${helper_dependency})
        endif()
    endforeach()

    ExternalProject_Add_Step(${external_project}
        invalidate-build
        COMMAND "${REAVEROS_HOST_BASH}" "${REAVEROS_SOURCE_DIR}/toolchain/invalidate-stale-build"
            "${REAVEROS_BINARY_DIR}" ${external_project}
            <BINARY_DIR> <INSTALL_DIR> "${identity}"
        DEPENDEES ${source_DEPENDEES}
        DEPENDERS configure
        DEPENDS ${dependency} ${helper_dependency}
    )
endfunction()

function(reaveros_add_ep_fetch_tag_target external_project revision)
    if (NOT ARGC EQUAL 2 OR "${revision}" STREQUAL "")
        message(FATAL_ERROR "Git source selection for '${external_project}' requires one revision.")
    endif()
    reaveros_require_host_tools("Upstream Git source selection" bash)
    ExternalProject_Get_Property(${external_project}
        STAMP_DIR GIT_REPOSITORY GIT_TAG UPDATE_DISCONNECTED)

    if (UPDATE_DISCONNECTED)
        set(update_step update_disconnected)
        set(patch_step patch_disconnected)
    else()
        set(update_step update)
        set(patch_step patch)
    endif()

    reaveros_file_dependency(tag_dependency "${external_project}-tag-inputs"
        "${GIT_TAG}:${revision}" "${REAVEROS_SOURCE_DIR}/toolchain/ensure-git-tag")

    ExternalProject_Add_Step(${external_project}
        set-to-tag
        COMMAND "${CMAKE_COMMAND}" -E env "GIT_EXECUTABLE=${GIT_EXECUTABLE}"
            "${REAVEROS_HOST_BASH}" "${REAVEROS_SOURCE_DIR}/toolchain/ensure-git-tag"
            <SOURCE_DIR> ${GIT_TAG} ${revision} ${GIT_REPOSITORY}
        DEPENDEES download
        DEPENDERS ${update_step} ${patch_step} configure build
        DEPENDS ${tag_dependency}
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
    )

    _reaveros_ep_refresh_stamps_after_build("${external_project}")
endfunction()
