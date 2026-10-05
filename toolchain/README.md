# Toolchain modes and policy

The superbuild configures children with generated `amd64-<mode>.cmake`
toolchain files. `targets.cmake` owns the supported architecture/mode identities
and mandatory ABI options. `identity.cmake` selects the compilers, target,
sysroot, lookup rules, and internal `REAVEROS_BUILD_MODE`; `options.cmake`
applies the target environment's compile and link requirements.

The modes are `freestanding`, `hosted`, `uefi`, and `tests`. The parent's
`REAVEROS_ENABLE_UNIT_TESTS` option creates additional native-test children;
it does not change the mode of ordinary OS children. The toolchain derives
the existing freestanding/UEFI compatibility booleans from the selected mode.

ABI requirements belong to the toolchain. General project policy lives in
`cmake/project_policy.cmake.in`, loaded after `project()`: C11/C++20 minimums,
required standards without language extensions, and warning defaults. Thorn
uses this policy with its native host compiler. Upstream CMake/LLVM projects
retain their own policy. Native-test debug information and libc++ selection
preserve the existing test environment; `CMAKE_BUILD_TYPE` retains its normal
CMake meaning.

Component-local requirements remain in their CMakeLists: kernel code model,
bootinit/static entry linkage, vDSO segment layout, runtime-library linkage,
loader assembly options, and service-specific RTTI settings. Shared machine
and mode ABI requirements remain in the toolchain.

Caller cache flags and `CFLAGS`, `CXXFLAGS`, and `ASMFLAGS` initialize the
ordinary CMake flag variables without being replaced. Warning defaults precede
caller flags, so compatible overrides such as `-Wno-error` work. Mandatory ABI
options follow ordinary flags; conflicting ABI options cannot redefine the
selected mode. Configuration-specific flags, linker flags, and compiler
launchers use CMake's normal handling. Reconfiguration leaves cache values
unchanged and does not accumulate policy options.

OS modes find programs on the host and headers, libraries, and packages in the
target sysroot. Tests search the project overlay first and retain host lookup
as a fallback. Initial compiler checks build static archives so an empty runtime
sysroot can bootstrap. After `project()` ordinary checks link executables again;
an explicit caller `CMAKE_TRY_COMPILE_TARGET_TYPE` setting is retained.

Freestanding and hosted OS consumers require linker-generated dependency files
for installed libraries and compiler-injected inputs. Static ABI probes do not
identify a linker, so shared project policy uses Clang's dry run and the pinned
CMake's linker-information modules after `project()`. This compatibility adapter
is isolated in `cmake/linker_policy.cmake`; it performs no runtime link during
bootstrap. Linking targets check effective capability, explicit disablement,
and `LINK_DEPENDS_NO_SHARED`. Native tests retain their ordinary target graph
and UEFI retains explicit COFF artifact dependencies.

Two platform adaptations remain intentional:

- ReaverOS with the Windows Clang target does not load CMake's Windows-Clang
  option table. UEFI therefore explicitly supplies the driver target, ASM
  sysroot, system include classification, and GNU-frontend linker wrapper.
- Native C executables link with the C++ driver to select the supplied C++
  runtime. C/C++ compilation and native C++ linking use standard CMake rules.

`ci/test-toolchain-modes <configured superbuild>` checks all four modes with the
installed patched tools. It covers caller/environment/configuration flags,
launchers, reuse, lookup, object ABI/formats, native runtime linkage, minimum
standards, and rejection of invalid compiler options. Cold component builds in
`ci/check-build-dependencies` run this check before rebuilding OS and test
components using their declared prerequisites.

`ci/test-child-cmake <configured superbuild>` checks actual independent producer
and consumer builds with installed archives: changed libraries relink without
recompilation, changed headers recompile, unchanged/reconfigured builds stay
unchanged, deleted archives can be restored, and whole-archive state is bounded.
It also checks caller shared-linker flags in rosestd, dependency-contract failures,
and compiler-free boot-protocol configuration in all four modes. Cold dependency
CI runs both contract suites using the installed patched tools.
