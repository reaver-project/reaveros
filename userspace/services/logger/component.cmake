set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_INSTALL_PATH [=[userspace/services/${_architecture}/system]=])
set(REAVEROS_COMPONENT_MODES hosted)
set(REAVEROS_COMPONENT_SKIP_MODE_NAME TRUE)
set(REAVEROS_COMPONENT_DEPENDS
    [=[all-${_architecture}-${_mode}-libraries]=]
    [=[kernel-${_architecture}]=]
)
