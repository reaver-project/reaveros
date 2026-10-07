set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_MODES freestanding hosted uefi tests)
set(REAVEROS_COMPONENT_INSTALL_PATH [=[sysroots/${_architecture}-${_mode}/layout with spaces]=])
set(REAVEROS_COMPONENT_DEPENDS [=[common-${_architecture}]=])
foreach (_mode IN LISTS REAVEROS_COMPONENT_MODES)
    string(TOUPPER "${_mode}" _mode_uppercase)
    set(REAVEROS_COMPONENT_DEPENDS_${_mode_uppercase}
        [=[${_mode}-first-${_architecture}]=]
        [=[${_mode}-second-${_architecture}]=]
    )
endforeach()
