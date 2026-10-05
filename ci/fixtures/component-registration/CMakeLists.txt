cmake_minimum_required(VERSION 3.31)
project(component-registration-test LANGUAGES NONE)

include(ExternalProject)
include("${TEST_REPOSITORY}/cmake/target_functions.cmake")
set(REAVEROS_BINARY_DIR "${CMAKE_BINARY_DIR}")
set(REAVEROS_CMAKE "${CMAKE_COMMAND}")
set(REAVEROS_ARCHITECTURES amd64)
set(_REAVEROS_CONFIGURE_HANDLED_BY_BUILD CONFIGURE_HANDLED_BY_BUILD TRUE)

_reaveros_expand_component_value(_text
    [=[first-${_architecture};second-${_mode};literal "quotes" and spaces]=]
    amd64 hosted "Registration fixture")
if (NOT _text STREQUAL [=[first-amd64;second-hosted;literal "quotes" and spaces]=])
    message(FATAL_ERROR "Metadata text and list boundaries changed during expansion.")
endif()

add_custom_target(toolchain-llvm-install)
add_custom_target(common-amd64
    COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_BINARY_DIR}/common-amd64")
foreach (_mode IN LISTS _reaveros_modes)
    file(WRITE "${CMAKE_BINARY_DIR}/install/toolchain/files/amd64-${_mode}.cmake"
        "set(REAVEROS_BUILD_MODE ${_mode})\nset(REAVEROS_FIXTURE_ROOT [==[${CMAKE_BINARY_DIR}]==])\n")
    foreach (_suffix first second)
        add_custom_target(${_mode}-${_suffix}-amd64
            COMMAND "${CMAKE_COMMAND}" -E touch "${CMAKE_BINARY_DIR}/${_mode}-${_suffix}-amd64")
    endforeach()
endforeach()
reaveros_add_aggregate_targets("")
reaveros_add_aggregate_targets_with_modes(libraries)

if (TEST_CASE STREQUAL "wrapper-unknown")
    reaveros_include_component(alpha PREFX library TAGS libraries)
elseif (TEST_CASE STREQUAL "wrapper-missing-value")
    reaveros_include_component(alpha BINARY_ROOT TAGS libraries)
elseif (NOT TEST_CASE OR TEST_CASE STREQUAL "metadata")
    # Optional fields must not inherit caller defaults into beta's declaration.
    set(REAVEROS_COMPONENT_DEPENDS_HOSTED accidental-caller-dependency)
    reaveros_include_component(alpha PREFIX library TAGS libraries)
    reaveros_include_component(beta PREFIX library TAGS libraries)
    reaveros_add_component(
        NAME internal SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/beta"
        BINARY_ROOT "${CMAKE_CURRENT_BINARY_DIR}" REGISTER_AGGREGATES FALSE
        ARCHITECTURES amd64 MODES hosted INSTALL_PATH [=[internal/${_architecture}]=]
        DEPENDS common-amd64
        CMAKE_ARGS "-DREGISTRATION_NOTE:STRING=literal words \${_architecture}-\${_mode}"
    )
else()
    set(_name alpha)
    set(_source "${CMAKE_CURRENT_SOURCE_DIR}/alpha")
    set(_root "${CMAKE_CURRENT_BINARY_DIR}")
    set(_install [=[sysroots/${_architecture}-${_mode}]=])
    set(_architectures amd64)
    set(_modes hosted)
    set(_skip FALSE)
    set(_unknown "")
    set(_depends common-amd64)
    if (TEST_CASE MATCHES "^missing-")
        string(REPLACE "missing-" "" _field "${TEST_CASE}")
        set(_${_field} "")
    elseif (TEST_CASE STREQUAL "unknown")
        set(_unknown TYPO value)
    elseif (TEST_CASE STREQUAL "architecture")
        set(_architectures typo)
    elseif (TEST_CASE STREQUAL "mode")
        set(_modes typo)
    elseif (TEST_CASE STREQUAL "duplicate-architecture")
        set(_architectures amd64 amd64)
    elseif (TEST_CASE STREQUAL "duplicate-mode")
        set(_modes hosted hosted)
    elseif (TEST_CASE STREQUAL "coordinate")
        unset(_reaveros_amd64_hosted_target)
    elseif (TEST_CASE STREQUAL "scalar-list")
        set(_source "${_source};${_source}")
    elseif (TEST_CASE STREQUAL "relative-root")
        set(_root relative)
    elseif (TEST_CASE STREQUAL "nonexistent-source")
        set(_source "${CMAKE_CURRENT_SOURCE_DIR}/absent")
    elseif (TEST_CASE STREQUAL "boolean")
        set(_skip banana)
    elseif (TEST_CASE STREQUAL "name-collision")
        set(_skip TRUE)
        set(_modes hosted freestanding)
    elseif (TEST_CASE STREQUAL "placeholder")
        set(_install [=[sysroots/${_archtecture}-${_mode}]=])
    elseif (TEST_CASE STREQUAL "dependency-placeholder")
        set(_depends [=[common-${_architecture_typo}]=])
    elseif (TEST_CASE STREQUAL "skip-mode")
        set(_skip TRUE)
        set(_modes hosted tests)
    elseif (NOT TEST_CASE STREQUAL "duplicate-target")
        message(FATAL_ERROR "Unknown test case '${TEST_CASE}'.")
    endif()
    foreach (_iteration RANGE 1 2)
        reaveros_add_component(${_unknown}
            NAME "${_name}" SOURCE_DIR "${_source}" BINARY_ROOT "${_root}"
            PREFIX library TAGS libraries
            ARCHITECTURES ${_architectures} MODES ${_modes}
            INSTALL_PATH "${_install}" SKIP_MODE_NAME "${_skip}"
            DEPENDS ${_depends}
        )
        if (NOT TEST_CASE STREQUAL "duplicate-target")
            break()
        endif()
    endforeach()
endif()

# Report the observable registration contract, including aggregate dependencies.
get_property(_targets DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
list(SORT _targets)
file(WRITE "${CMAKE_BINARY_DIR}/registration.txt" "")
foreach (_target IN LISTS _targets)
    foreach (_property MANUALLY_ADDED_DEPENDENCIES
            _REAVEROS_COMPONENT_LABELS _REAVEROS_COMPONENT_TEST_NAME)
        get_target_property(_value "${_target}" "${_property}")
        file(APPEND "${CMAKE_BINARY_DIR}/registration.txt"
            "${_target}\t${_property}\t${_value}\n")
    endforeach()
endforeach()
