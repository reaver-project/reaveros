include_guard(GLOBAL)

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
    set(_scalar_fields NAME SOURCE_DIR BINARY_ROOT PREFIX INSTALL_PATH
        SKIP_MODE_NAME REGISTER_AGGREGATES INSTALL_TRANSFER_FROM)
    cmake_parse_arguments(PARSE_ARGV 0 _component
        "" "${_scalar_fields}"
        "ARCHITECTURES;MODES;TAGS;CMAKE_ARGS;INSTALL_TRANSFER_ROOTS;${_dependency_fields}")

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
    if (NOT DEFINED _component_REGISTER_AGGREGATES)
        set(_component_REGISTER_AGGREGATES TRUE)
    endif()
    foreach (_field SKIP_MODE_NAME REGISTER_AGGREGATES)
        string(TOUPPER "${_component_${_field}}" _component_${_field})
        if (NOT _component_${_field} MATCHES "^(ON|OFF|TRUE|FALSE|YES|NO|Y|N|0|1)$")
            message(FATAL_ERROR "${_context}: ${_field} must be a boolean.")
        endif()
    endforeach()
    if ((_component_INSTALL_TRANSFER_FROM AND NOT _component_INSTALL_TRANSFER_ROOTS)
            OR (_component_INSTALL_TRANSFER_ROOTS AND NOT _component_INSTALL_TRANSFER_FROM))
        message(FATAL_ERROR "${_context}: install transfer requires both FROM and ROOTS.")
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
            _reaveros_expand_component_value(_cmake_args "${_component_CMAKE_ARGS}"
                "${_architecture}" "${_mode}" "${_context}")
            set(_project_prefix "${_component_BINARY_ROOT}/${_component_name}-prefix")

            set(_transfer_file "")
            if (_component_INSTALL_TRANSFER_FROM)
                _reaveros_expand_component_value(_transfer_from "${_component_INSTALL_TRANSFER_FROM}"
                    "${_architecture}" "${_mode}" "${_context}")
                _reaveros_expand_component_value(_transfer_roots "${_component_INSTALL_TRANSFER_ROOTS}"
                    "${_architecture}" "${_mode}" "${_context}")
                string(JOIN "\n" _transfer_roots ${_transfer_roots})
                set(_transfer_file "${REAVEROS_BINARY_DIR}/cmake/install-transfers/${_component_name}.txt")
                file(GENERATE OUTPUT "${_transfer_file}" CONTENT "${_transfer_from}\n${_transfer_roots}\n")
            endif()

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
                    "-DREAVEROS_INSTALL_TRANSFER_FILE=${_transfer_file}"
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
                    ${_cmake_args}
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

            if (_component_REGISTER_AGGREGATES)
                reaveros_register_target(${_component_name} ${_architecture} ${_mode}
                    ${_component_TAGS} ${_component_NAME})
            endif()

            if (_mode STREQUAL "tests" AND _component_REGISTER_AGGREGATES)
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
        REAVEROS_COMPONENT_CMAKE_ARGS
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
        CMAKE_ARGS ${REAVEROS_COMPONENT_CMAKE_ARGS}
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
