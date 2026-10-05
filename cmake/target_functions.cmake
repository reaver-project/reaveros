include("${CMAKE_CURRENT_LIST_DIR}/../toolchain/targets.cmake")

function(_reaveros_add_target_maybe_tests _name)
    add_custom_target(${_name})
    if (REAVEROS_ENABLE_UNIT_TESTS)
        add_custom_target(${_name}-build-tests)
    endif()
endfunction()

function(_reaveros_add_aggregate_targets_impl _suffix _use_modes)
    if (NOT "${_suffix}" STREQUAL "")
        _reaveros_add_target_maybe_tests(all-${_suffix})
        set(_suffix "-${_suffix}")
    else()
        add_custom_target(all-build-tests)
    endif()

    foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
        _reaveros_add_target_maybe_tests(all-${architecture}${_suffix})
    endforeach()

    if (_use_modes)
        set(_modes uefi freestanding hosted)
        if (REAVEROS_ENABLE_UNIT_TESTS)
            list(APPEND _modes tests)
        endif()
        foreach (mode IN LISTS _modes)
            add_custom_target(all-${mode}${_suffix})
            foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
                add_custom_target(all-${architecture}-${mode}${_suffix})
            endforeach()
        endforeach()
    endif()
endfunction()

function(reaveros_add_aggregate_targets_with_modes _suffix)
    _reaveros_add_aggregate_targets_impl("${_suffix}" TRUE)
endfunction()

function(reaveros_add_aggregate_targets _suffix)
    _reaveros_add_aggregate_targets_impl("${_suffix}" FALSE)
endfunction()

function(_reaveros_register_target_impl _target _head _tail)
    list(LENGTH _tail _tail_length)
    math(EXPR _tail_length_prev "${_tail_length} - 1")
    list(GET _tail ${_tail_length_prev} _last)

    get_target_property(_is_test_target ${_target} _REAVEROS_IS_TEST_TARGET)

    foreach (_index RANGE 0 ${_tail_length_prev})
        list(GET _tail ${_index} _current_element)
        set(_full_list ${_head} ${_current_element})

        if (${_index} EQUAL ${_tail_length_prev} OR NOT "${_last}" STREQUAL "build-tests")
            string(REPLACE ";" "-" _aggregate_target "${_full_list}")
            if (TARGET all-${_aggregate_target})
                set(_is_relevant_aggregate TRUE)
                if (_is_test_target)
                    list(FIND _full_list "tests" _has_tests)
                    list(FIND _full_list "build-tests" _has_build_tests)
                    if (${_has_tests} EQUAL -1 AND ${_has_build_tests} EQUAL -1)
                        set(_is_relevant_aggregate FALSE)
                    endif()
                endif()

                if (_is_relevant_aggregate)
                    add_dependencies(all-${_aggregate_target} ${_target})
                endif()
            endif()
        endif()

        math(EXPR _index_next "${_index} + 1")

        if (${_index_next} LESS ${_tail_length})
            list(SUBLIST _tail ${_index_next} -1 _current_tail)

            _reaveros_register_target_impl(${_target} "${_full_list}" "${_current_tail}")
        endif()
    endforeach()
endfunction()

function(reaveros_register_target _target)
    _reaveros_register_target_impl(${_target} "" "${ARGN}")
endfunction()

function(_reaveros_expand_component_value _output _input _architecture _mode _context)
    set(_value "${_input}")
    # Add supported placeholders here; substitute text without another CMake parse.
    foreach (_placeholder IN ITEMS _architecture _mode)
        string(REPLACE "\${${_placeholder}}" "${${_placeholder}}" _value "${_value}")
    endforeach()
    if (_value MATCHES "\\$\\{")
        message(FATAL_ERROR
            "${_context}: unknown or malformed metadata placeholder in '${_input}'.")
    endif()
    set(${_output} "${_value}" PARENT_SCOPE)
endfunction()

# Internal registration contract. Scalar paths and names are quoted; coordinates,
# tags, and dependencies are lists. Mode dependencies augment the common list.
# Component-specific compiler requirements belong in the child's CMakeLists.
function(reaveros_add_component)
    set(_dependency_fields DEPENDS)
    foreach (_mode IN LISTS _reaveros_modes)
        string(TOUPPER "${_mode}" _mode_uppercase)
        list(APPEND _dependency_fields "DEPENDS_${_mode_uppercase}")
    endforeach()
    set(_scalar_fields NAME SOURCE_DIR BINARY_ROOT PREFIX INSTALL_PATH SKIP_MODE_NAME)
    cmake_parse_arguments(PARSE_ARGV 0 _component
        "" "${_scalar_fields}" "ARCHITECTURES;MODES;TAGS;${_dependency_fields}")

    set(_context "Component '${_component_NAME}' (${_component_SOURCE_DIR})")
    if (_component_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR
            "${_context}: unknown registration arguments: ${_component_UNPARSED_ARGUMENTS}")
    endif()
    foreach (_field NAME SOURCE_DIR BINARY_ROOT INSTALL_PATH ARCHITECTURES MODES)
        if (NOT DEFINED _component_${_field} OR "${_component_${_field}}" STREQUAL "")
            message(FATAL_ERROR "${_context}: missing ${_field}.")
        endif()
    endforeach()
    foreach (_field IN LISTS _scalar_fields)
        if (_field IN_LIST _component_KEYWORDS_MISSING_VALUES AND NOT _field STREQUAL "PREFIX")
            message(FATAL_ERROR "${_context}: ${_field} requires a value.")
        endif()
        list(LENGTH _component_${_field} _length)
        if (_length GREATER 1)
            message(FATAL_ERROR "${_context}: ${_field} must be a scalar, not a list.")
        endif()
    endforeach()
    if (NOT IS_DIRECTORY "${_component_SOURCE_DIR}"
            OR NOT EXISTS "${_component_SOURCE_DIR}/CMakeLists.txt")
        message(FATAL_ERROR "${_context}: SOURCE_DIR must contain a CMakeLists.txt.")
    endif()
    foreach (_field SOURCE_DIR BINARY_ROOT)
        if (NOT IS_ABSOLUTE "${_component_${_field}}")
            message(FATAL_ERROR "${_context}: ${_field} must be an absolute path.")
        endif()
    endforeach()
    if (NOT DEFINED _component_SKIP_MODE_NAME)
        set(_component_SKIP_MODE_NAME FALSE)
    endif()
    string(TOUPPER "${_component_SKIP_MODE_NAME}" _component_SKIP_MODE_NAME)
    if (NOT _component_SKIP_MODE_NAME MATCHES "^(ON|OFF|TRUE|FALSE|YES|NO|Y|N|0|1)$")
        message(FATAL_ERROR "${_context}: SKIP_MODE_NAME must be a boolean.")
    endif()

    foreach (_field ARCHITECTURES MODES)
        string(TOLOWER "${_field}" _field_lowercase)
        set(_allowed "${_reaveros_${_field_lowercase}}")
        set(_seen "")
        foreach (_value IN LISTS _component_${_field})
            if (NOT _value IN_LIST _allowed)
                message(FATAL_ERROR "${_context}: unsupported ${_field} value '${_value}'.")
            endif()
            if (_value IN_LIST _seen)
                message(FATAL_ERROR "${_context}: duplicate ${_field} value '${_value}'.")
            endif()
            list(APPEND _seen "${_value}")
        endforeach()
    endforeach()
    if (_component_SKIP_MODE_NAME)
        set(_ordinary_modes "${_component_MODES}")
        list(REMOVE_ITEM _ordinary_modes tests)
        list(LENGTH _ordinary_modes _length)
        if (_length GREATER 1)
            message(FATAL_ERROR
                "${_context}: SKIP_MODE_NAME would give multiple modes the same target name.")
        endif()
    endif()

    message(STATUS "Adding component ${_component_SOURCE_DIR}...")
    set(_target_stem "${_component_NAME}")
    if (NOT "${_component_PREFIX}" STREQUAL "")
        string(PREPEND _target_stem "${_component_PREFIX}-")
    endif()

    foreach (_architecture IN LISTS _component_ARCHITECTURES)
        foreach (_mode IN LISTS _component_MODES)
            if (NOT DEFINED _reaveros_${_architecture}_${_mode}_target)
                message(FATAL_ERROR
                    "${_context}: unsupported architecture/mode '${_architecture}/${_mode}'.")
            endif()
            if (_mode STREQUAL "tests" AND NOT REAVEROS_ENABLE_UNIT_TESTS)
                continue()
            endif()

            # Native tests always include their mode, including kernel tests.
            if (_component_SKIP_MODE_NAME AND NOT _mode STREQUAL "tests")
                set(_component_name "${_target_stem}-${_architecture}")
            else()
                set(_component_name "${_target_stem}-${_mode}-${_architecture}")
            endif()
            if (TARGET "${_component_name}")
                message(FATAL_ERROR "${_context}: target '${_component_name}' is already registered.")
            endif()
            string(TOUPPER "${_mode}" _mode_uppercase)
            set(_dependency_templates ${_component_DEPENDS} ${_component_DEPENDS_${_mode_uppercase}})
            _reaveros_expand_component_value(_depends "${_dependency_templates}"
                "${_architecture}" "${_mode}" "${_context}")
            _reaveros_expand_component_value(_install_path "${_component_INSTALL_PATH}"
                "${_architecture}" "${_mode}" "${_context}")
            set(_project_prefix "${_component_BINARY_ROOT}/${_component_name}-prefix")

            ExternalProject_Add(${_component_name}
                EXCLUDE_FROM_ALL TRUE
                PREFIX "${_project_prefix}"
                BINARY_DIR "${_project_prefix}/src/${_component_name}-build"

                DOWNLOAD_COMMAND ""
                SOURCE_DIR "${_component_SOURCE_DIR}"
                BUILD_ALWAYS 1

                DEPENDS toolchain-llvm-install ${_depends}

                INSTALL_DIR "${REAVEROS_BINARY_DIR}/install/${_install_path}"

                ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

                INSTALL_COMMAND "${CMAKE_COMMAND}"
                    "-DREAVEROS_BUILD_ROOT=${REAVEROS_BINARY_DIR}"
                    "-DREAVEROS_INSTALL_PROJECT=${_component_name}"
                    "-DREAVEROS_INSTALL_BINARY_DIR=<BINARY_DIR>"
                    "-DREAVEROS_INSTALL_CMAKE=${REAVEROS_CMAKE}"
                    -P "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/install_component.cmake"

                CMAKE_COMMAND "${REAVEROS_CMAKE}"
                CMAKE_ARGS
                    --no-warn-unused-cli
                    "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
                    "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}"
                    "-DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}"
                    "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
                    "-DCMAKE_TOOLCHAIN_FILE=${REAVEROS_BINARY_DIR}/install/toolchain/files/${_architecture}-${_mode}.cmake"
                    "-DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>"
                    "-DREAVEROS_ARCH=${_architecture}"
                    "-DREAVEROS_THORN=${REAVEROS_THORN}"
            )

            # Existing child manifests let the ownership check adopt a build
            # configured before the superbuild started tracking installations.
            ExternalProject_Get_Property(${_component_name} BINARY_DIR STAMP_DIR TMP_DIR)
            file(GENERATE
                OUTPUT "${REAVEROS_BINARY_DIR}/cmake/install-projects/${_component_name}.txt"
                CONTENT "${BINARY_DIR}/install_manifest.txt\n"
            )
            file(GENERATE
                OUTPUT "${REAVEROS_BINARY_DIR}/cmake/component-build-directories/${_component_name}.txt"
                CONTENT "${BINARY_DIR}\n${STAMP_DIR}\n${TMP_DIR}\n"
            )

            if (_mode STREQUAL "tests")
                set_target_properties("${_component_name}"
                    PROPERTIES
                        _REAVEROS_IS_TEST_TARGET TRUE
                )
            else()
                set_target_properties("${_component_name}"
                    PROPERTIES
                        _REAVEROS_IS_TEST_TARGET FALSE
                )
            endif()

            reaveros_register_target(${_component_name} ${_architecture} ${_mode}
                ${_component_TAGS} ${_component_NAME})

            if (_mode STREQUAL "tests")
                reaveros_register_target(${_component_name} ${_architecture} ${_mode}
                    ${_component_TAGS} ${_component_NAME} build-tests)

                set_property(GLOBAL APPEND PROPERTY _REAVEROS_COMPONENTS "${_component_name}")
                if (NOT _component_NAME STREQUAL "kernel")
                    set(_labels "${_architecture};${_component_TAGS};${_target_stem}")
                else()
                    set(_labels "${_architecture};${_component_TAGS}")
                endif()
                set_target_properties("${_component_name}"
                    PROPERTIES
                        _REAVEROS_COMPONENT_LABELS "${_labels}"
                        _REAVEROS_COMPONENT_TEST_NAME "${_target_stem}-${_architecture}"
                )
            endif()
        endforeach()
    endforeach()
endfunction()

# Keep component.cmake as the declaration format. Optional dependency fields are
# empty by default and cannot inherit values from another component or the caller.
function(reaveros_include_component _directory)
    cmake_parse_arguments(PARSE_ARGV 1 _registration "" "PREFIX;BINARY_ROOT" "TAGS")
    set(_missing_values "${_registration_KEYWORDS_MISSING_VALUES}")
    list(REMOVE_ITEM _missing_values PREFIX TAGS)
    if (_registration_UNPARSED_ARGUMENTS OR _missing_values)
        message(FATAL_ERROR
            "Component '${_directory}': invalid inclusion arguments: ${_registration_UNPARSED_ARGUMENTS} ${_missing_values}")
    endif()
    if (NOT DEFINED _registration_BINARY_ROOT)
        set(_registration_BINARY_ROOT "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    set(_component_vars
        REAVEROS_COMPONENT_ARCHITECTURES
        REAVEROS_COMPONENT_INSTALL_PATH
        REAVEROS_COMPONENT_MODES
        REAVEROS_COMPONENT_SKIP_MODE_NAME
        REAVEROS_COMPONENT_DEPENDS
    )
    foreach (_mode IN LISTS _reaveros_modes)
        string(TOUPPER "${_mode}" _mode_uppercase)
        list(APPEND _component_vars "REAVEROS_COMPONENT_DEPENDS_${_mode_uppercase}")
    endforeach()
    foreach (_variable IN LISTS _component_vars)
        set(${_variable} "")
    endforeach()
    set(REAVEROS_COMPONENT_SKIP_MODE_NAME FALSE)

    include("${_directory}/component.cmake")

    get_cmake_property(_metadata_variables VARIABLES)
    list(FILTER _metadata_variables INCLUDE REGEX "^REAVEROS_COMPONENT_")
    foreach (_variable IN LISTS _metadata_variables)
        if (NOT _variable IN_LIST _component_vars)
            message(FATAL_ERROR
                "Component '${_directory}' (${CMAKE_CURRENT_SOURCE_DIR}/${_directory}): unknown metadata field '${_variable}'.")
        endif()
    endforeach()

    set(_mode_dependencies "")
    foreach (_mode IN LISTS _reaveros_modes)
        string(TOUPPER "${_mode}" _mode_uppercase)
        list(APPEND _mode_dependencies "DEPENDS_${_mode_uppercase}"
            ${REAVEROS_COMPONENT_DEPENDS_${_mode_uppercase}})
    endforeach()
    reaveros_add_component(
        NAME "${_directory}"
        SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/${_directory}"
        BINARY_ROOT "${_registration_BINARY_ROOT}"
        PREFIX "${_registration_PREFIX}"
        TAGS ${_registration_TAGS}
        ARCHITECTURES ${REAVEROS_COMPONENT_ARCHITECTURES}
        MODES ${REAVEROS_COMPONENT_MODES}
        INSTALL_PATH "${REAVEROS_COMPONENT_INSTALL_PATH}"
        SKIP_MODE_NAME "${REAVEROS_COMPONENT_SKIP_MODE_NAME}"
        DEPENDS ${REAVEROS_COMPONENT_DEPENDS}
        ${_mode_dependencies}
    )
endfunction()

function(reaveros_automatic_components _prefix)
    # Userspace discovery is intentional; libraries/services use explicit lists
    # and loaders iterate only the user's selected loader names.
    file(GLOB _directories RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" CONFIGURE_DEPENDS *)

    foreach (_directory IN LISTS _directories)
        if (IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${_directory}"
                AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${_directory}/component.cmake"
        )
            reaveros_include_component("${_directory}" PREFIX "${_prefix}" TAGS ${ARGN})
        endif()
    endforeach()
endfunction()

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

function(_reaveros_add_ep_file_dependencies external_project step)
    # Add_StepDependencies also adds target dependencies, so it cannot accept
    # files once the step has its own target. Make uses these single-config stamps.
    ExternalProject_Get_Property(${external_project} STAMP_DIR)
    add_custom_command(APPEND
        OUTPUT "${STAMP_DIR}/${external_project}-${step}"
        DEPENDS ${ARGN}
    )
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
