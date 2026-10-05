set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_MODES freestanding hosted uefi tests)
set(REAVEROS_COMPONENT_INSTALL_PATH [=[sysroots/${_architecture}-${_mode}/layout with spaces]=])
set(REAVEROS_COMPONENT_DEPENDS [=[common-${_architecture}]=])
