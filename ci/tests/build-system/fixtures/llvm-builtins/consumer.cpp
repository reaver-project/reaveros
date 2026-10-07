#include <cstdio>
extern "C" int fixture_builtin();
int main() { std::printf("%d\n", fixture_builtin()); }
