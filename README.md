# ReaverOS

A new iteration, from "scratch", of a µkernel-based operating system for 64-bit architectures. Previous iteration can be found
here: https://github.com/griwes/reaveros-iteration1.

## Building ReaverOS

### Dependencies

ReaverOS' build system bootstraps most tools that it uses as build tools, but not all the tools the tools it bootstraps depend
on themselves. That being said, we are trying to keep the dependencies of the build system to a minimum. Currently, those
dependencies are:

* CMake (3.12 or higher);
* Python (3.7 or higher);
* Git;
* Bison;
* Flex;
* cpio;
* OpenSSL;
* C and C++ compilers;
* Make.

On a recent apt-based systems, the following command should fulfill the dependencies:

```
apt install build-essential automake cmake git python3 bison flex libssl-dev
```

### Build considerations

ReaverOS builds the full toolchain that it uses for all builds internally, at versions fixed as git tags. This means that to
build ReaverOS, you need internet access to fetch the repositories for the entire toolchain.

This also means that an initial build using a given toolchain will take a long time, because it will build full LLVM.
Two docker images containing pre-built binaries are available:

* `ghcr.io/reaver-project/reaveros-build-env` contains just the necessary files, and not the toolchain checkouts and build directories
(for mechanics of this, see notes about `prune` targets below). This has an advantage of making the image smaller, but will
require rebuild from scratch (although using ccache) if any of the toolchain elements change.
* `ghcr.io/reaver-project/reaveros-build-env/unpruned`, which is exactly the same as above, but prior to running `all-toolchain-prune`.
This has the advantage of not requiring a full rebuild of the toolchain when they change - at the price of a much larger size.
(At the time of writing, about 1GiB for the pruned image vs 7GiB for the unpruned one.)

The images expect the root directory of the git repository mounted in /reaveros. A possible way to achieve this is to:

```bash
git clone https://github.com/reaver-project/reaveros
docker run -v $(pwd):/reaveros -it <image>
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

The build uses the normal CMake C and C++ compiler heuristics to detect what compiler to use for building all the various tools
used during the build. Additionally, the following options are exposed:

* `REAVEROS_USE_CACHE` - enable using a caching application for builds (this could be `ccache`, `sccache`, but also other
compiler launchers like `icecc`);
* `REAVEROS_CACHE_PROGRAM` - specify the binary for the caching application (defaults to `ccache`);
* `REAVEROS_ARCHITECTURES` - select the target CPU architectures to be enabled; currently only `amd64` is supported;
* `REAVEROS_LOADERS` - select the bootloaders to be enabled; currently only `uefi` is supported.
* `REAVEROS_ENABLE_UNIT_TESTS` - controls whether the build configuration includes unit tests for all components.

### Build targets

ReaverOS' build system doesn't add any targets as a dependency of `all`, due to the sheer amount of targets an eventual full
configuration will require. Instead, it provides more fine grained aggregate targets. There is too many of those to list them
here; you can run `make help` to see them all. They should be self explanatory, but to name a few as an example:

* `all-loaders-uefi` - will build UEFI bootloaders for all enabled architectures;
* `all-amd64-hosted-libraries` - will build all usermode libraries for amd64.

Some of the aggregate targets are not useful and are only generated to allow for code simplicity in the functions creating them;
for instance, `all-hosted-loaders` is not a reasonable target to run, because bootloaders only use freestanding environments.

There are also targets for the specific components of the build, for instance:

* `toolchain`;
* `library-rosestd-freestanding-amd64`;
* `image-uefi-efipart-amd64`.

There's one more group of targets that are of note - the prune targets. All toolchain targets have an associated prune target,
and there also exists an aggregate `all-toolchain-prune` target. Their role is to remove the source and build directories of
a given (or all) toolchain subprojects, to reduce the build directory size; since all the toolchain installs into subdirectories
of `install/toolchain`, the source and build directories aren't needed to build all of ReaverOS targets.

Do keep in mind that this means that if a version of a pruned toolchain changes, you will need to re-download the sources,
re-configure the project, and rebuild it fully; since the compilers used by ReaverOS can (and will) take a long time to compile,
you should be very careful of pruning a toolchain if you disabled build caching (see `REAVEROS_USE_CACHE` above), built enough
files to have your cache evict the previous stored build results, and do not wish to possibly wait for full LLVM builds
to finish whenever you pull the main branch.

### Running the OS (as far as it goes, at least)

This last mentioned target - `image-uefi-efipart-amd64` - will create a file containing a FAT filesystem image that includes
the UEFI bootloader for the amd64 architecture. If you install QEMU and OVMF, you can then run it and see what happens with a
command like this (this is the exact command I have been using to test at the time of these words being written on a Debian
sid):

```bash
qemu-system-x86_64 -bios /usr/share/ovmf/OVMF.fd -drive format=raw,file=install/images/uefi-efipart-amd64.img -monitor stdio -serial file:/dev/stdout -cpu qemu64,+sse3,+sse4.1,+sse4.2 -m 2048 -smp 4 -vga std -M q35 -global hpet.msi=on -netdev user,id=net0 -device e1000e,romfile=,netdev=net0
```

Platform requirements:
* `amd64`:
1. UEFI.
2. HPET w/ FSB interrupt delivery; this is achieved in QEMU with `-global hpet.msi=on`.

### Unit tests

For testing, there's two kinds of interesting CMake targets:
* `library-rosestd-tests-amd64`, which builds all tests of a specific component, and
* `all-build-tests` and more fine-grained like `all-libraries-build-tests`, which aggregate the above targets.

After the tests for a specific configuration have been built, they can be run with `ctest`. By default, all enabled tests for
all enabled components for all enabled architectures are run. The set of tests to be run can be controlled using test labels;
to see a list of labels available on a given configuration, run `ctest --print-labels`. To run tests matching a specific label,
use `ctest -L`. See the `ctest` documentation for further instructions.

For convenience, an additional target - `run-tests` - is exposed. This target is equivalent to building the `all-build-tests`
target, followed by running `ctest` with no arguments.
