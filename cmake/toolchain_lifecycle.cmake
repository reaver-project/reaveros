include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/external_project_make.cmake")

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
    file(MAKE_DIRECTORY "${REAVEROS_BINARY_DIR}/toolchain")
    if (EXISTS "${_dependency}")
        file(READ "${_dependency}" _previous_hash)
    else()
        set(_previous_hash "")
    endif()
    if (NOT _previous_hash STREQUAL _inputs_hash)
        file(WRITE "${_dependency}" "${_inputs_hash}")
    endif()

    set(${output_file} "${_dependency}" PARENT_SCOPE)
endfunction()

function(reaveros_patch_dependency output_file external_project source_revision)
    reaveros_file_dependency(_dependency "${external_project}-patch-inputs"
        "${source_revision}" ${ARGN})
    set(${output_file} "${_dependency}" PARENT_SCOPE)
endfunction()

function(reaveros_add_ep_prune_target external_project)
    ExternalProject_Get_Property(${external_project} STAMP_DIR UPDATE_DISCONNECTED)

    cmake_parse_arguments(prune "REMOVE_DOWNLOADED_ARCHIVE;SOURCE_STEP_AFTER_PATCH" "SOURCE_STEP" "" ${ARGN})
    if (prune_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unexpected prune target options: ${prune_UNPARSED_ARGUMENTS}")
    endif()
    if (prune_SOURCE_STEP)
        set(source_step "${prune_SOURCE_STEP}")
    else()
        set(source_step set-to-tag)
    endif()

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
    cmake_parse_arguments(source "" "" "DEPENDEES" ${ARGN})
    if (source_UNPARSED_ARGUMENTS OR NOT source_DEPENDEES)
        message(FATAL_ERROR "Invalid source identity step for ${external_project}")
    endif()

    set(dependency "${REAVEROS_BINARY_DIR}/toolchain/${external_project}-source-inputs")
    file(MAKE_DIRECTORY "${REAVEROS_BINARY_DIR}/toolchain")
    if (EXISTS "${dependency}")
        file(READ "${dependency}" previous_identity)
    else()
        set(previous_identity "")
    endif()
    if (NOT previous_identity STREQUAL "${identity}\n")
        file(WRITE "${dependency}" "${identity}\n")
    endif()

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
        COMMAND bash ${REAVEROS_SOURCE_DIR}/toolchain/invalidate-stale-build
            "${REAVEROS_BINARY_DIR}" ${external_project}
            <BINARY_DIR> <INSTALL_DIR> "${identity}"
        DEPENDEES ${source_DEPENDEES}
        DEPENDERS configure
        DEPENDS ${dependency} ${helper_dependency}
    )
endfunction()

function(reaveros_add_ep_fetch_tag_target external_project revision)
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
            bash "${REAVEROS_SOURCE_DIR}/toolchain/ensure-git-tag"
            <SOURCE_DIR> ${GIT_TAG} ${revision} ${GIT_REPOSITORY}
        DEPENDEES download
        DEPENDERS ${update_step} ${patch_step} configure build
        DEPENDS ${tag_dependency}
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
    )

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
