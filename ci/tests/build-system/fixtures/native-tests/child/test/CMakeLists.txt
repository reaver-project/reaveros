add_compile_definitions(LOCAL_TEST_DEFINITION)
reaveros_add_native_tests(LIBRARIES fixture-library)

set(_working "${CMAKE_CURRENT_BINARY_DIR}/working with spaces")
file(MAKE_DIRECTORY "${_working}")
set(_probe "${CMAKE_CURRENT_SOURCE_DIR}/probe.py")
set(_name [=[command [names]; with "quotes"]=])
add_test(NAME "${_name}" COMMAND "${Python3_EXECUTABLE}" "${_probe}"
    probe "${TEST_COMPONENT}" "$<CONFIG>" "${_working}"
    "argument with space" "semicolon;argument" [=[back\slash]=] [=[endswith\]=]
    [=[unbalanced[;brackets]=] [=[literal ${variable} and $ENV{variable}]=]
    [=[embedded "quotes"]=] "" "\nleading newline" "carriage\rreturn" "tab\tvalue")
set_tests_properties("${_name}" PROPERTIES
    WORKING_DIRECTORY "${_working}" TIMEOUT 12
    ENVIRONMENT "PROBE_ENV=value\\;with semi;COMPONENT=${TEST_COMPONENT}"
    ENVIRONMENT_MODIFICATION "MODIFIED=set:initial;MODIFIED=string_append: suffix"
    LABELS "child;command"
    PASS_REGULAR_EXPRESSION "PROBE_OK ${TEST_COMPONENT}"
    FIXTURES_REQUIRED state)

add_test(NAME setup COMMAND "${Python3_EXECUTABLE}" "${_probe}" setup "${TEST_COMPONENT}")
add_test(NAME cleanup COMMAND "${Python3_EXECUTABLE}" "${_probe}" cleanup "${TEST_COMPONENT}")
set_tests_properties(setup PROPERTIES FIXTURES_SETUP state WORKING_DIRECTORY "${_working}")
set_tests_properties(cleanup PROPERTIES FIXTURES_CLEANUP state WORKING_DIRECTORY "${_working}")

add_test(NAME dependent COMMAND "${Python3_EXECUTABLE}" "${_probe}" dependent "${TEST_COMPONENT}")
string(REPLACE ";" "\\;" _dependency "${_name}")
set_tests_properties(dependent PROPERTIES DEPENDS "${_dependency}" WORKING_DIRECTORY "${_working}")

add_test(NAME expected-failure COMMAND "${Python3_EXECUTABLE}" -c "raise SystemExit(7)")
set_tests_properties(expected-failure PROPERTIES WILL_FAIL TRUE TIMEOUT 3)
add_test(NAME actual-failure COMMAND "${Python3_EXECUTABLE}" -c "raise SystemExit(9)")
add_test(NAME skip COMMAND "${Python3_EXECUTABLE}" -c "raise SystemExit(77)")
set_tests_properties(skip PROPERTIES SKIP_RETURN_CODE 77)
add_test(NAME disabled COMMAND "${Python3_EXECUTABLE}" -c "raise SystemExit(9)")
set_tests_properties(disabled PROPERTIES DISABLED TRUE)
add_test(NAME configured COMMAND "${Python3_EXECUTABLE}" -c "import sys; print(sys.argv[1])" "$<CONFIG>")
set_tests_properties(configured PROPERTIES
    PASS_REGULAR_EXPRESSION "$<CONFIG>" TIMEOUT "$<IF:$<CONFIG:Release>,4,7>")
add_test(NAME resources COMMAND "${Python3_EXECUTABLE}" -c "pass")
set_tests_properties(resources PROPERTIES RESOURCE_GROUPS "2,widgets:1")
add_test(NAME timeout-after-match COMMAND "${Python3_EXECUTABLE}" -c "print('milestone')")
set_tests_properties(timeout-after-match PROPERTIES TIMEOUT_AFTER_MATCH "3;milestone")
