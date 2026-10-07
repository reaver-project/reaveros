if (EXISTS "${TEST_CONTROL}/fail-build")
    message(FATAL_ERROR "Intentional build failure")
endif()
