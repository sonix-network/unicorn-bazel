"""Bazel build of Unicorn 2.1.4, derived from google/silifuzz third_party/BUILD.unicorn.

Sources, defines and include order follow Unicorn's CMakeLists.txt for a
GCC/Clang host. Every include directory is passed as a private `-I` so that
QEMU's internal headers (several targets ship a `cpu.h`) never reach
consumers; only `include/unicorn/*.h` is exported.
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

# "" in this repository's own workspace, "external/<canonical name>" otherwise.
_ROOT = Label("//:BUILD.bazel").workspace_root

def _path(relative):
    return _ROOT + "/" + relative if _ROOT else relative

def _includes(directories):
    return ["-I" + _path(directory) for directory in directories]

# CMakeLists.txt include_directories(), then the host TCG backend that
# add_compile_options() appends, then the generated config-host.h.
_COMMON_INCLUDES = [
    "glib_compat",
    "qemu",
    "qemu/include",
    "include",
    "qemu/tcg",
    "qemu/tcg/i386",
    "bazel/config",
]

# add_compile_options() for non-MSVC, plus UNICORN_CFLAGS for an x86-64 host.
_COPTS = [
    "-m64",
    "-mcx16",
    "-D_GNU_SOURCE",
    "-D_FILE_OFFSET_BITS=64",
    "-D_LARGEFILE_SOURCE",
    "-fPIC",
    # QEMU 5 sources predate many current GCC/Clang default warnings; keep
    # consumers' output readable without changing code generation.
    "-w",
] + _includes(_COMMON_INCLUDES)

# Linux x86-64 is the only host this overlay has configuration for.
HOST_COMPATIBILITY = [
    "@platforms//os:linux",
    "@platforms//cpu:x86_64",
]

def test_copts(defines):
    """Copts for the upstream unit tests, which include config-host.h."""
    return ["-w"] + defines + _includes(["bazel/config"])

def internal_headers():
    """Every header QEMU sources may include."""
    return native.glob([
        "bazel/config/**/*.h",
        "glib_compat/*.h",
        "include/**/*.h",
        "qemu/**/*.h",
    ])

def textual_includes():
    """`.inc.c` files: #included C fragments that must not be compiled alone."""
    return native.glob(["qemu/**/*.inc.c"])

# CMakeLists.txt UNICORN_COMMON_SRCS for a POSIX host.
COMMON_SRCS = [
    "list.c",
    "glib_compat/glib_compat.c",
    "glib_compat/gtestutils.c",
    "glib_compat/garray.c",
    "glib_compat/gtree.c",
    "glib_compat/grand.c",
    "glib_compat/glist.c",
    "glib_compat/gmem.c",
    "glib_compat/gpattern.c",
    "glib_compat/gslice.c",
    "qemu/util/bitmap.c",
    "qemu/util/bitops.c",
    "qemu/util/crc32c.c",
    "qemu/util/cutils.c",
    "qemu/util/getauxval.c",
    "qemu/util/guest-random.c",
    "qemu/util/host-utils.c",
    "qemu/util/osdep.c",
    "qemu/util/qdist.c",
    "qemu/util/qemu-timer.c",
    "qemu/util/qemu-timer-common.c",
    "qemu/util/range.c",
    "qemu/util/qht.c",
    "qemu/util/pagesize.c",
    "qemu/util/cacheinfo.c",
    "qemu/crypto/aes.c",
    "qemu/util/oslib-posix.c",
    "qemu/util/qemu-thread-posix.c",
]

# CMakeLists.txt UNICORN_ARCH_COMMON: compiled once per guest target.
ARCH_COMMON_SRCS = [
    "qemu/exec.c",
    "qemu/exec-vary.c",
    "qemu/softmmu/cpus.c",
    "qemu/softmmu/ioport.c",
    "qemu/softmmu/memory.c",
    "qemu/softmmu/memory_mapping.c",
    "qemu/fpu/softfloat.c",
    "qemu/tcg/optimize.c",
    "qemu/tcg/tcg.c",
    "qemu/tcg/tcg-op.c",
    "qemu/tcg/tcg-op-gvec.c",
    "qemu/tcg/tcg-op-vec.c",
    "qemu/accel/tcg/cpu-exec.c",
    "qemu/accel/tcg/cpu-exec-common.c",
    "qemu/accel/tcg/cputlb.c",
    "qemu/accel/tcg/tcg-all.c",
    "qemu/accel/tcg/tcg-runtime.c",
    "qemu/accel/tcg/tcg-runtime-gvec.c",
    "qemu/accel/tcg/translate-all.c",
    "qemu/accel/tcg/translator.c",
    "qemu/softmmu/unicorn_vtlb.c",
]

# CMakeLists.txt UNICORN_SRCS.
LIB_SRCS = [
    "uc.c",
    "qemu/softmmu/vl.c",
    "qemu/hw/core/cpu.c",
]

def unicorn_common(name):
    cc_library(
        name = name,
        srcs = COMMON_SRCS + internal_headers(),
        textual_hdrs = textual_includes(),
        # CMake sets C_VISIBILITY_PRESET hidden on unicorn-common because it
        # links one libunicorn. Bazel may link each cc_library as its own .so
        # (cc_test's dynamic mode), so these symbols must stay visible.
        copts = _COPTS,
        linkopts = ["-lpthread"],
        target_compatible_with = HOST_COMPATIBILITY,
        visibility = ["//visibility:private"],
    )

def unicorn_softmmu(name, softmmu, target_dir, srcs, common):
    """One QEMU front end (`<softmmu>-softmmu` in CMakeLists.txt).

    Args:
      name: target name.
      softmmu: QEMU target name, e.g. "arm"; selects `qemu/<softmmu>.h`, the
        symbol-renaming header CMake force-includes, and its config-target.h.
      target_dir: directory under qemu/target holding the front end.
      srcs: the target-specific sources listed in CMakeLists.txt.
      common: label of the unicorn_common library.
    """
    cc_library(
        name = name,
        srcs = ARCH_COMMON_SRCS + srcs + internal_headers(),
        textual_hdrs = textual_includes(),
        copts = _COPTS + [
            "-DNEED_CPU_H",
            "-include",
            _path("qemu/%s.h" % softmmu),
        ] + _includes([
            "bazel/config/%s-softmmu" % softmmu,
            "qemu/target/" + target_dir,
        ]),
        deps = [common],
        target_compatible_with = HOST_COMPATIBILITY,
        visibility = ["//visibility:private"],
    )

def unicorn_library(name, archs, softmmus, **kwargs):
    """The public library: uc.c built for a set of guest architectures.

    Args:
      name: target name.
      archs: Unicorn architecture names, e.g. ["ARM", "ARM64"]; each becomes
        `-DUNICORN_HAS_<ARCH>` as in CMakeLists.txt.
      softmmus: labels of the unicorn_softmmu front ends for those archs.
      **kwargs: passed to cc_library (e.g. visibility).
    """
    cc_library(
        name = name,
        srcs = LIB_SRCS + internal_headers(),
        textual_hdrs = textual_includes(),
        hdrs = native.glob(["include/unicorn/*.h"]),
        strip_include_prefix = "include",
        copts = _COPTS + ["-DUNICORN_HAS_%s" % arch for arch in archs],
        deps = softmmus,
        target_compatible_with = HOST_COMPATIBILITY,
        **kwargs
    )
