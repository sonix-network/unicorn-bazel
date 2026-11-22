"""Bazel build of Unicorn 2.1.4, derived from google/silifuzz third_party/BUILD.unicorn.

Sources, defines and include order follow Unicorn's CMakeLists.txt: its
GCC/Clang branch on Linux and its MSVC branch on Windows. Every include
directory is passed as a private `-I` so that QEMU's internal headers (several
targets ship a `cpu.h`) never reach consumers; only `include/unicorn/*.h` is
exported.
"""

load("@rules_cc//cc:cc_library.bzl", "cc_library")

# "" in this repository's own workspace, "external/<canonical name>" otherwise.
_ROOT = Label("//:BUILD.bazel").workspace_root

_LINUX = "@platforms//os:linux"
_WINDOWS = "@platforms//os:windows"

def _path(relative):
    return _ROOT + "/" + relative if _ROOT else relative

def _includes(directories):
    # cl.exe accepts -I as well as /I.
    return ["-I" + _path(directory) for directory in directories]

def _per_os(linux, windows):
    return select({_LINUX: linux, _WINDOWS: windows})

# Where config-host.h and <target>-softmmu/config-target.h come from: the
# overlay's configure output on Linux, Unicorn's own msvc/ tree on Windows
# (CMakeLists.txt puts msvc/ first on the include path for MSVC).
def _config_dirs(softmmu = None):
    suffix = "/%s-softmmu" % softmmu if softmmu else ""
    return _per_os(
        _includes(["bazel/config" + suffix]),
        _includes(["msvc" + suffix]),
    )

# CMakeLists.txt include_directories(), then the host TCG backend that
# add_compile_options() adds on both branches.
_COMMON_INCLUDES = [
    "glib_compat",
    "qemu",
    "qemu/include",
    "include",
    "qemu/tcg",
    "qemu/tcg/i386",
]

# add_compile_options() for each branch, plus UNICORN_CFLAGS for an x86-64
# GCC/Clang host. Warnings are silenced: QEMU 5 sources predate many current
# compiler defaults, and this keeps consumers' output readable without
# changing code generation.
_OS_COPTS = _per_os(
    [
        "-m64",
        "-mcx16",
        "-D_GNU_SOURCE",
        "-D_FILE_OFFSET_BITS=64",
        "-D_LARGEFILE_SOURCE",
        "-fPIC",
        "-w",
    ],
    [
        "-Dinline=__inline",
        "-D__func__=__FUNCTION__",
        "-D_CRT_SECURE_NO_WARNINGS",
        "-DWIN32_LEAN_AND_MEAN",
        "-D__x86_64__",
        "/w",
    ],
)

def _copts(softmmu = None):
    return _OS_COPTS + _config_dirs() + _includes(_COMMON_INCLUDES) + (
        _config_dirs(softmmu) if softmmu else []
    )

# x86-64 Linux (GCC/Clang) and x86-64 Windows (MSVC) are the hosts this overlay
# has configuration for.
HOST_COMPATIBILITY = select({
    _LINUX: [],
    _WINDOWS: [],
    "//conditions:default": ["@platforms//:incompatible"],
}) + ["@platforms//cpu:x86_64"]

def test_copts(defines):
    """Copts for the upstream unit tests, which include config-host.h."""
    return _per_os(["-w"], ["/w"]) + defines + _config_dirs()

def internal_headers():
    """Every header QEMU sources may include."""
    return native.glob([
        "bazel/config/**/*.h",
        "glib_compat/*.h",
        "include/**/*.h",
        "msvc/**/*.h",
        "qemu/**/*.h",
    ])

def textual_includes():
    """`.inc.c` files: #included C fragments that must not be compiled alone."""
    return native.glob(["qemu/**/*.inc.c"])

# CMakeLists.txt UNICORN_COMMON_SRCS, then its per-OS additions.
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
]

_OS_COMMON_SRCS = _per_os(
    [
        "qemu/util/oslib-posix.c",
        "qemu/util/qemu-thread-posix.c",
    ],
    [
        "qemu/util/oslib-win32.c",
        "qemu/util/qemu-thread-win32.c",
        # Calls _setjmp with a NULL frame so longjmp does not try to unwind
        # through generated code (see qemu/include/sysemu/os-win32.h).
        "qemu/util/setjmp-wrapper-win32.asm",
    ],
)

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
        srcs = COMMON_SRCS + _OS_COMMON_SRCS + internal_headers(),
        textual_hdrs = textual_includes(),
        # CMake sets C_VISIBILITY_PRESET hidden on unicorn-common (a no-op for
        # MSVC). These libraries are static-only, so every consumer links them
        # into one image.
        copts = _copts() + _per_os(["-fvisibility=hidden"], []),
        linkopts = _per_os(["-lpthread"], []),
        # Static only, as upstream links one libunicorn: no per-library .so.
        linkstatic = True,
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
    header = _path("qemu/%s.h" % softmmu)
    cc_library(
        name = name,
        srcs = ARCH_COMMON_SRCS + srcs + internal_headers(),
        textual_hdrs = textual_includes(),
        copts = _copts(softmmu) + ["-DNEED_CPU_H"] + _per_os(
            ["-include", header],
            ["/FI" + header],
        ) + _includes(["qemu/target/" + target_dir]),
        deps = [common],
        # Static only, as upstream links one libunicorn: no per-library .so.
        linkstatic = True,
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
        copts = _copts() + ["-DUNICORN_HAS_%s" % arch for arch in archs],
        deps = softmmus,
        # Static only, as upstream links one libunicorn: no per-library .so.
        linkstatic = True,
        target_compatible_with = HOST_COMPATIBILITY,
        **kwargs
    )
