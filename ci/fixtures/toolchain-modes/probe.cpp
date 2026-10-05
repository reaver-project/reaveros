#ifndef REAVEROS_USER_CXX
#error User C++ flags were lost
#endif
#ifndef REAVEROS_USER_CONFIGURATION
#error User configuration-specific C++ flags were lost
#endif
static_assert(__cplusplus >= 202002L, "C++20 requirement");
static_assert(sizeof(void *) == 8, "AMD64 pointer ABI");
#ifdef EXPECT_WINDOWS_ABI
static_assert(sizeof(long) == 4, "UEFI Windows ABI");
#endif
#if defined(EXPECT_FREESTANDING) && (defined(__EXCEPTIONS) || defined(__GXX_RTTI))
#error Required freestanding C++ ABI options were lost
#endif
extern "C" int cpp_mode_probe() { return sizeof(void *); }
