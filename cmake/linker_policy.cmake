include_guard(GLOBAL)

if ((REAVEROS_BUILD_MODE STREQUAL "freestanding" OR REAVEROS_BUILD_MODE STREQUAL "hosted")
        AND NOT DEFINED CMAKE_LINK_DEPENDS_USE_LINKER)
    set(CMAKE_LINK_DEPENDS_USE_LINKER TRUE)
endif()

# Static compiler bootstrap probes cannot discover a linker. Reuse the pinned
# CMake's compiler-output parser and linker modules on Clang's dry run instead;
# this identifies the actual driver-selected linker without linking a runtime.
# These internal CMake entry points are deliberately isolated here and covered
# by the toolchain contract tests.
macro(_reaveros_initialize_linker_information language)
    string(TOUPPER "${CMAKE_BUILD_TYPE}" _reaveros_link_configuration)
    separate_arguments(_reaveros_link_flags NATIVE_COMMAND
        "${CMAKE_${language}_FLAGS} ${CMAKE_${language}_FLAGS_${_reaveros_link_configuration}} ${CMAKE_EXE_LINKER_FLAGS} ${CMAKE_EXE_LINKER_FLAGS_${_reaveros_link_configuration}}")
    if (CMAKE_LINKER_TYPE AND NOT CMAKE_LINKER_TYPE STREQUAL "DEFAULT")
        list(APPEND _reaveros_link_flags ${CMAKE_${language}_USING_LINKER_${CMAKE_LINKER_TYPE}})
    endif()
    set(_reaveros_driver_target "--target=${CMAKE_${language}_COMPILER_TARGET}")
    if (CMAKE_SYSROOT)
        list(APPEND _reaveros_driver_target "--sysroot=${CMAKE_SYSROOT}")
    endif()
    if ("${language}" STREQUAL "CXX")
        set(_reaveros_probe_language c++)
    else()
        set(_reaveros_probe_language c)
    endif()
    execute_process(COMMAND "${CMAKE_${language}_COMPILER}"
        ${_reaveros_driver_target} ${_reaveros_link_flags}
        "-###" -x "${_reaveros_probe_language}" /dev/null -o /dev/null
        RESULT_VARIABLE _reaveros_driver_result
        OUTPUT_VARIABLE _reaveros_driver_output ERROR_VARIABLE _reaveros_driver_output)
    if (NOT _reaveros_driver_result EQUAL 0)
        message(FATAL_ERROR "Could not inspect the ReaverOS ${language} linker:\n${_reaveros_driver_output}")
    endif()
    include(CMakeParseImplicitLinkInfo)
    include(Internal/CMakeDetermineLinkerId)
    cmake_parse_implicit_link_info2("${_reaveros_driver_output}" _reaveros_link_log ""
        COMPUTE_LINKER _reaveros_linker LANGUAGE "${language}")
    if (NOT _reaveros_linker)
        message(FATAL_ERROR "Could not identify the ReaverOS ${language} linker:\n${_reaveros_driver_output}")
    endif()
    set(CMAKE_${language}_COMPILER_LINKER "${_reaveros_linker}")
    cmake_determine_linker_id("${language}" "${_reaveros_linker}")
    # Compiler metadata from static ABI probes serializes an empty capability.
    # Let CMake test it; preserve an explicitly supplied TRUE/FALSE value.
    if (CMAKE_${language}_LINKER_DEPFILE_SUPPORTED STREQUAL "")
        unset(CMAKE_${language}_LINKER_DEPFILE_SUPPORTED)
    endif()
    include(Internal/CMake${language}LinkerInformation)
endmacro()

function(reaveros_require_linker_dependencies target language)
    # OS consumers link artifacts installed by other children and injected by
    # the compiler driver. Native tests use their ordinary target graph; UEFI
    # uses explicit COFF library paths. Neither needs the ELF contract here.
    if (REAVEROS_BUILD_MODE STREQUAL "freestanding" OR REAVEROS_BUILD_MODE STREQUAL "hosted")
        get_target_property(_reaveros_no_shared "${target}" LINK_DEPENDS_NO_SHARED)
        if (NOT CMAKE_LINK_DEPENDS_USE_LINKER
                OR _reaveros_no_shared
                OR NOT CMAKE_${language}_LINKER_DEPFILE_SUPPORTED
                OR NOT CMAKE_${language}_LINKER_DEPFILE_FLAGS)
            message(FATAL_ERROR
                "ReaverOS ${REAVEROS_BUILD_MODE} target '${target}' requires linker-generated dependencies. "
                "CMAKE_LINK_DEPENDS_USE_LINKER must be enabled and the selected ${language} "
                "linker '${CMAKE_${language}_COMPILER_LINKER}' must support dependency files; "
                "LINK_DEPENDS_NO_SHARED must be disabled.")
        endif()
    endif()
endfunction()
