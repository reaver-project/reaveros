# ReaverOS

A new iteration, from "scratch", of a µkernel-based operating system for 64-bit architectures. Previous iteration can be found
here: https://github.com/griwes/reaveros-iteration1.

## Building ReaverOS

### Dependencies

ReaverOS' build system bootstraps most tools that it uses as build tools, but not all the tools the tools it bootstraps depend
on themselves. That being said, we are trying to keep the dependencies of the build system to a minimum. Currently, those
dependencies are (on a Linux host):

* CMake (3.31 or higher);
* Python (3.9 or higher);
* Git;
* Bison;
* Flex;
* Bash, GNU find and cpio, awk, grep, tail, and fallocate;
* Autoconf, Automake (including aclocal), and M4 for the UEFI filesystem tools;
* OpenSSL;
* C and C++ compilers;
* GNU Make. The supported CMake generator is `Unix Makefiles`.

Toolchain lifecycle guards also use Linux `/proc`, file locks, and pidfds.
The superbuild checks required host tools while configuring the enabled features
and passes their resolved paths to helpers and child projects. Autotools runs with
private aliases for the selected executables so its nested commands use the same selection.

On Debian Trixie, or another apt-based system providing CMake 3.31 or newer,
the following command should fulfill the dependencies:

```
apt install build-essential automake cmake git python3 bison flex cpio libssl-dev xz-utils
```

### Build considerations

ReaverOS builds the full toolchain that it uses for all builds internally, at versions fixed as git tags. This means that to
build ReaverOS, you need internet access to fetch the repositories for the entire toolchain.

This also means that an initial build using a given toolchain will take a long time, because it will build full LLVM.
CI publishes two Docker images containing pre-built binaries:

* `ghcr.io/reaver-project/reaveros-build-env` contains just the necessary files, and not the toolchain checkouts and build directories
(for mechanics of this, see notes about `prune` targets below). This has an advantage of making the image smaller, but will
require rebuild from scratch (although using ccache) if any of the toolchain elements change.
* `ghcr.io/reaver-project/reaveros-build-env/unpruned`, which is exactly the same as above, but prior to running `all-toolchain-prune`.
This has the advantage of not requiring a full rebuild of the toolchain when they change - at the price of a much larger size.

The images expect the root directory of the git repository mounted in /reaveros. A possible way to achieve this is to:

```bash
git clone https://github.com/reaver-project/reaveros
docker run -v "$(pwd):/reaveros" -it <image>
# <image> is one of the URLs listed above
```

Inside the container, `cd /build`; from there, you can run all the normal ReaverOS build targets, as described below. To move
the images out of the container (to be able to run them with QEMU, for instance), you can create a directory in your checkout
directory and move appropriate files from within the build directory into that directory:

```bash
cd /reaveros
mkdir build-results
cd /build
make all-images
cp install/images/uefi-efipart-amd64.img /reaveros/build-results
```

Alternatively, you can create another docker volume, with `-v`, and copy the results there.

Keep in mind that if you terminate the docker container, you will need to rebuild the ReaverOS code itself - but the build should
be fairly quick regardless.

The docker images are keyed by every tracked toolchain input, including local
patches. CI reuses an exact content match, rebuilds when those inputs change,
and refreshes the container operating system on the weekly scheduled run. If a
git pull changes the toolchain inputs, restart the docker container and pull
the matching image before continuing.

The AWS CI architecture, authorization policy, cache promotion flow, and
required repository variables are documented in `ci/aws/README.md`.

### Configuration options

Configure out of source with the Make generator, for example:

```bash
cmake -S . -B build -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=Debug
make -C build all-images -j4
```

The build uses the normal CMake C and C++ compiler heuristics to detect what compiler to use for building all the various tools
used during the build. Additionally, the following options are exposed:

* `REAVEROS_USE_CACHE` - enable using a caching application for builds (this could be `ccache`, `sccache`, but also other
compiler launchers like `icecc`);
* `REAVEROS_CACHE_PROGRAM` - specify the binary for the caching application (defaults to `ccache`);
* `REAVEROS_ARCHITECTURES` - select the target CPU architectures to be enabled; currently only `amd64` is supported;
* `REAVEROS_LOADERS` - select the bootloaders to be enabled; currently only `uefi` is supported.
* `REAVEROS_ENABLE_UNIT_TESTS` - include native test components and their build targets (defaults to off).

The superbuild configures each component in a separate build directory with its
freestanding, hosted, UEFI, or native-test toolchain. `REAVEROS_BUILD_MODE` is set
internally for those children. Enabling native tests adds test builds alongside
the ordinary OS builds; it does not switch the OS components into native-test mode.
Each child's installation is staged with checked file ownership. Independently
requesting a component builds and installs its declared prerequisites.

### Build targets

ReaverOS' build system doesn't add any targets as a dependency of `all`, due to the sheer amount of targets an eventual full
configuration will require. Instead, it provides more fine grained aggregate targets. There is too many of those to list them
here; you can run `make help` to see them all. They should be self explanatory, but to name a few as an example:

* `all-loaders-uefi` - will build UEFI bootloaders for all enabled architectures;
* `all-amd64-hosted-libraries` - will build all usermode libraries for amd64;
* `all-toolchain` - will build the selected upstream tools and in-tree Thorn;
* `all-images` - will build the selected OS images.

Aggregate targets combine component categories, architectures, and modes. The
available combinations depend on the selected components; `make help` lists them.

There are also targets for the specific components of the build, for instance:

* `toolchain-llvm-install`;
* `library-rosestd-freestanding-amd64`;
* `image-uefi-efipart-amd64`.

The upstream CMake, LLVM, dosfstools, and mtools projects each have a prune target,
such as `toolchain-llvm-prune`; `all-toolchain-prune` groups the selected ones.
In-tree Thorn has no prune target. Pruning validates a completed installation,
then removes sources/build trees while preserving `install/toolchain` outputs for
subsequent component builds. An incomplete or interrupted installation fails that
validation. `make clean` preserves upstream toolchain caches.

Source, patch, and output-affecting configuration identities determine whether an
installed cache can be reused. Changing only compiler launchers or LLVM link-job
scheduling preserves it. Missing installed outputs trigger recovery. Prune and
build/install operations for the same upstream project cannot share a Make
invocation or overlap across Make invocations in the same build directory;
conflicting requests fail explicitly. Different projects have independent guards.

Do keep in mind that this means that if a version of a pruned toolchain changes, you will need to re-download the sources,
re-configure the project, and rebuild it fully; since the compilers used by ReaverOS can (and will) take a long time to compile,
you should be very careful of pruning a toolchain if you disabled build caching (see `REAVEROS_USE_CACHE` above), built enough
files to have your cache evict the previous stored build results, and do not wish to possibly wait for full LLVM builds
to finish whenever you pull the main branch.

Image targets intentionally package on every request. Each owns its staging tree
and declares its resulting image as a byproduct. Packaging replaces the completed
image only on success. The UEFI FAT image retains its 1,474,560-byte layout; a
preflight check accounts for formatted filesystem overhead and rounded allocations
and rejects an oversized payload before copying it.

Packaging identical installed payloads with the same intended executable modes,
geometry, epoch, and packaging-tool versions produces identical image bytes.
`SOURCE_DATE_EPOCH` selects the packaging time; its default is 315532800
(1980-01-01 UTC), and the supported range is 315532800 through 4294967295.
Packaging fixes the locale/timezone, sorts initrd paths, records root ownership,
normalizes permissions and timestamps, and uses a fixed FAT allocation order and
content-derived volume ID. FAT timestamps have two-second precision. Filesystem
metadata normalization affects fresh staging trees, leaving installed artifacts
and sources intact. Public image targets still package on every request.

This is reproducibility of packaging already-built payloads. Fresh source builds
can differ: Thorn intentionally randomizes syscall IDs, and compiler/debug paths
and PE timestamps are other binary-level inputs. Thorn's randomization is retained.

### Running the OS (as far as it goes, at least)

This last mentioned target - `image-uefi-efipart-amd64` - will create a file containing a FAT filesystem image that includes
the UEFI bootloader for the amd64 architecture. With QEMU, OVMF, and access to
`/dev/kvm`, the same four-CPU boot smoke used by CI can run it:

```bash
./ci/helpers/smoke-test-uefi-amd64 build/install/images/uefi-efipart-amd64.img boot.log
```

Platform requirements:
* `amd64`:
1. UEFI.
2. HPET w/ FSB interrupt delivery; this is achieved in QEMU with `-global hpet.msi=on`.

### Unit tests

For testing, there's two kinds of interesting CMake targets:
* `library-rosestd-tests-amd64`, which builds all tests of a specific component, and
* `all-build-tests` and more fine-grained like `all-libraries-build-tests`, which aggregate the above targets.

Configure with `-DREAVEROS_ENABLE_UNIT_TESTS=ON` to include native test components
and their individual build targets. The root `all-build-tests` aggregate also
exists as an empty target when tests are disabled.
Native test executables retain assertions in Debug and Release.

After the tests for a specific configuration have been built, they can be run with `ctest`. By default, all enabled tests for
all enabled components for all enabled architectures are run. The set of tests to be run can be controlled using test labels;
to see a list of labels available on a given configuration, run `ctest --print-labels`. To run tests matching a specific label,
use `ctest -L`. See the `ctest` documentation for further instructions.

For convenience, an additional target - `run-tests` - is exposed. This target is equivalent to building the `all-build-tests`
target, followed by running `ctest` with no arguments.
