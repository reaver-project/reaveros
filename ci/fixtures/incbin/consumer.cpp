#include <cstdint>
#include <cstdio>

extern "C" const char begin_bootinit[], end_bootinit[], begin_vdso[], end_vdso[];

int main()
{
    std::printf("%zu %zu\n",
        static_cast<std::size_t>(reinterpret_cast<std::uintptr_t>(end_bootinit)
            - reinterpret_cast<std::uintptr_t>(begin_bootinit)),
        static_cast<std::size_t>(reinterpret_cast<std::uintptr_t>(end_vdso)
            - reinterpret_cast<std::uintptr_t>(begin_vdso)));
}
