# Unicorn Bazel registry

A standalone Bazel index registry, in the Bazel Central Registry (BCR) layout,
for the [Unicorn](https://github.com/unicorn-engine/unicorn) CPU emulator.
Bazel downloads the upstream Unicorn 2.1.4 release archive, verifies its
SHA-256 and applies the checked-in overlay pinned in
[`source.json`](modules/unicorn/2.1.4.bcr.2/source.json). No CMake, Ninja or
`configure` run at build time.

**This downstream overlay is AI-generated. It is not part of upstream Unicorn
and is not supported by the Unicorn project.** It is derived from the Bazel
build in [google/silifuzz](https://github.com/google/silifuzz) (see
[NOTICE](NOTICE)). If it proves useful, the plan is to offer it upstream.

## Scope

- **Hosts** (2.1.4.bcr.2), each built and tested in CI with Bazel 8 and 9:

  | Host | Compiler in CI |
  | --- | --- |
  | Linux x86-64 | GCC; also hermetic Zig/Clang |
  | Linux AArch64 | GCC |
  | macOS AArch64 (Apple silicon) | Apple Clang |
  | macOS x86-64 | Apple Clang |
  | Windows x86-64 | MSVC (`cl.exe`, `ml64`) |

  Other hosts, including Windows AArch64 and MinGW, are marked incompatible.
  Versions 2.1.4 and 2.1.4.bcr.1 support Linux x86-64 only.
- **Guest architectures:** 32-bit ARM, AArch64 and x86 (16/32/64-bit).
  Unicorn's other front ends (MIPS, PPC, RISC-V, SPARC, m68k, s390x,
  TriCore) are not built yet.
- **Not included:** Unicorn's language bindings and samples.

## Using it

```starlark
bazel_dep(name = "unicorn", version = "2.1.4.bcr.2")
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
- The libraries are static-only (`linkstatic = True`), like upstream's single
  `libunicorn`, so `cc_test`, `cc_binary` and Rust consumers all link the
  front ends into one image. Version 2.1.4 was not static-only: a
  dynamically linked `cc_test` or `rust_test` failed to load or link the
  front ends there. Use 2.1.4.bcr.1 or later.

## How the overlay relates to upstream

- Source lists, defines and include order follow Unicorn 2.1.4's
  `CMakeLists.txt` (`UNICORN_COMMON_SRCS`, `UNICORN_ARCH_COMMON`, the
  `*-softmmu` libraries and `UNICORN_SRCS`):
  - its GCC/Clang branch on Linux and macOS;
  - its MSVC branch on Windows, which adds the Win32 sources and the
    `setjmp` wrapper assembled by `ml64`.
- The host TCG backend follows the host CPU (`qemu/tcg/i386` or
  `qemu/tcg/aarch64`).
- `bazel/config/<os>-<cpu>/` holds each POSIX host's output of Unicorn's own
  `qemu/configure` and `qemu/scripts/create_config`, run as `CMakeLists.txt`
  runs them (the unused `CONFIG_IASL` line dropped). Each header names the
  compiler it was probed with and fails with `#error` on another host.
  - Linux x86-64 was probed locally with Clang and matches silifuzz's header.
  - The others were probed on GitHub's runners.
  - The manual [probe workflow](.github/workflows/probe-config.yml)
    regenerates them.
- On Windows the config headers are Unicorn's own `msvc/` tree, as for its
  MSVC build.
- Every QEMU include directory is a private `-I`. Only
  `include/unicorn/*.h` is exported, so QEMU's internal headers (several
  targets ship a `cpu.h`) never reach consumers.
- `unicorn-common` is built with hidden visibility, as upstream's
  `C_VISIBILITY_PRESET` does; that is safe because the libraries are
  static-only (2.1.4 omitted it).

## Build and test

With Bazel 9.3.2 (or Bazelisk). `dev` needs Linux x86-64; `dev/bcr` runs on
any supported host:

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
