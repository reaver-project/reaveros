#include <cassert>

#ifdef NDEBUG
#error "Native test assertions are disabled"
#endif
#ifndef LOCAL_TEST_DEFINITION
#error "Component-local test definitions were lost"
#endif
int fixture_value();
int main()
{
    int calls = 0;
    assert(++calls == 1);
    assert(fixture_value() == 37);
    return calls != 1;
}
