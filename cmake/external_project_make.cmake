include_guard(GLOBAL)

function(_reaveros_add_ep_file_dependencies external_project step)
    # Add_StepDependencies also adds target dependencies, so it cannot accept
    # files once the step has its own target. Make uses these single-config stamps.
    ExternalProject_Get_Property(${external_project} STAMP_DIR)
    add_custom_command(APPEND
        OUTPUT "${STAMP_DIR}/${external_project}-${step}"
        DEPENDS ${ARGN}
    )
endfunction()
