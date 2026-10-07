#ifndef REAVEROS_USER_C
#error User C flags were lost
#endif
#ifndef REAVEROS_USER_CONFIGURATION
#error User configuration-specific C flags were lost
#endif
#ifdef EXPECT_QUOTED_SYSROOT
#include <reaveros-quoted-sysroot.h>
_Static_assert(REAVEROS_QUOTED_SYSROOT == 37, "Quoted UEFI system include path");
#endif
_Static_assert(__STDC_VERSION__ >= 201112L, "C11 requirement");
_Static_assert(sizeof(void *) == 8, "AMD64 pointer ABI");
#ifdef EXPECT_WINDOWS_ABI
_Static_assert(sizeof(long) == 4, "UEFI Windows ABI");
#else
_Static_assert(sizeof(long) == 8, "ELF LP64 ABI");
#endif
#if defined(EXPECT_FREESTANDING) && !defined(__ROSE_FREESTANDING)
#error Required freestanding definition was lost
#endif
int c_mode_probe(void) { return sizeof(void *); }
