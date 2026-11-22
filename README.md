# Unicorn Bazel registry

A standalone Bazel index registry, in the Bazel Central Registry (BCR) layout,
for the [Unicorn](https://github.com/unicorn-engine/unicorn) CPU emulator.
Bazel downloads the upstream Unicorn 2.1.4 release archive, verifies its
SHA-256 and applies the checked-in overlay pinned in
[`source.json`](modules/unicorn/2.1.4/source.json). No CMake, Ninja or
`configure` run at build time.

**This downstream overlay is AI-generated. It is not part of upstream Unicorn
and is not supported by the Unicorn project.** It is derived from the Bazel
build in [google/silifuzz](https://github.com/google/silifuzz) (see
[NOTICE](NOTICE)). If it proves useful, the plan is to offer it upstream.

## Scope

- **Host:** Linux x86-64 only. Other hosts fail with an explicit `#error` in
  the generated `config-host.h` and are marked incompatible.
- **Guest architectures:** 32-bit ARM, AArch64 and x86 (16/32/64-bit).
  Unicorn's other front ends (MIPS, PPC, RISC-V, SPARC, m68k, s390x,
  TriCore) are not built yet.
- **Not included:** Unicorn's language bindings and samples.

## Using it

```starlark
bazel_dep(name = "unicorn", version = "2.1.4")
```

with this registry ahead of the BCR:

```
common --registry=https://raw.githubusercontent.com/sonix-network/unicorn-bazel/main
common --registry=https://bcr.bazel.build
```

Depend on exactly one of these targets and `#include <unicorn/unicorn.h>`:

| Target | Guest architectures |
| --- | --- |
| `@unicorn//:unicorn` | ARM, AArch64, x86 |
| `@unicorn//:unicorn_arm` | ARM |
| `@unicorn//:unicorn_arm64` | AArch64 |
| `@unicorn//:unicorn_x86` | x86 |

Each variant builds `uc.c` with its own `UNICORN_HAS_<ARCH>` defines, so two
variants must not be linked into one binary.

Notes for consumers:

- Build with `-c opt` for a usable emulator. Like upstream's default CMake
  build, the overlay sets no optimization level of its own.
- `cc_test` links dynamically by default. Bazel's per-library shared objects
  do not record their dependencies on each other, so a test that calls only
  the public API would not load the guest front ends. Set
  `linkstatic = True` on such tests; `cc_binary` and Rust link statically
  already.

## How the overlay relates to upstream

- Source lists, defines and include order follow Unicorn 2.1.4's
  `CMakeLists.txt` for a GCC/Clang host (`UNICORN_COMMON_SRCS`,
  `UNICORN_ARCH_COMMON`, the `*-softmmu` libraries and `UNICORN_SRCS`).
- `bazel/config/` holds the output of Unicorn's own `qemu/configure` and
  `qemu/scripts/create_config`, run as `CMakeLists.txt` runs them, with Clang
  and `-m64 -mcx16` (the unused `CONFIG_IASL` line dropped). The host header
  matches silifuzz's.
- Every QEMU include directory is a private `-I`. Only
  `include/unicorn/*.h` is exported, so QEMU's internal headers (several
  targets ship a `cpu.h`) never reach consumers.
- Unlike upstream, `unicorn-common` is not built with hidden visibility,
  because Bazel may link each library as its own shared object.

## Build and test

On Linux x86-64 with Bazel 9.3.2 (or Bazelisk):

```sh
python3 dev/tools/pin_sources.py --check      # overlay pins match the files
(cd dev && bazel test @unicorn//:all)         # hermetic Zig toolchain
(cd dev/bcr && bazel test @unicorn//:all)     # host compiler, like the BCR presubmit
```

The tests are Unicorn's upstream unit tests (`tests/unit`: `test_arm`,
`test_arm64`, `test_x86`, `test_mem`, `test_ctl`; `test_arm` also against
the ARM-only variant). A `variant_test_*` per library checks that it opens
exactly its own architectures and rejects the others.

After editing anything under `overlay/`, run
`python3 dev/tools/pin_sources.py` to refresh `source.json`. The dev
workspaces disable the lockfile, but a running Bazel server keeps the old
registry contents: run `bazel shutdown` before rebuilding.

## Versions

Published versions are immutable. For build-only fixes against the same
upstream archive, add `2.1.4.bcr.1`, `2.1.4.bcr.2`, and so on, keeping the
directory name, `module(version = ...)` and `metadata.json` in sync.
