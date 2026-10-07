#if defined(EXPECT_RELEASE) && !defined(NDEBUG)
#error "The test assertion override leaked into its library"
#endif
int fixture_value()
{
    return 37;
}
