.intel_syntax noprefix
.ifndef REAVEROS_USER_ASM
.error "User ASM flags were lost"
.endif
.ifndef REAVEROS_CONFIGURATION_ASM
.error "User configuration-specific ASM flags were lost"
.endif
.text
.globl asm_mode_probe
asm_mode_probe:
    xor eax, eax
    ret
