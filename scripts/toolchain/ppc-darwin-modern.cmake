# CMake toolchain: cross-compiling for PowerPC Mac OS X from Linux with the
# GCC 14 toolchain, for a current WebKit (2.52). The WebKit 604 engine keeps
# using ppc-darwin.cmake and GCC 6.5; this file is that one with the modern
# prefix, C++23 in GNU mode, and no _GLIBCXX_USE_C99_MATH_TR1 workaround
# (GCC 14's libstdc++ does not need it).
# Installed as /opt/ppc-modern/share/ppc-darwin-modern.cmake by build-modern-deps.sh.
# Built against the 10.5 SDK with a 10.4 deployment target, so Leopard-only
# functions are weakly linked and simply absent on Tiger.
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR ppc)  # the name WebKit CMake recognises
set(CMAKE_SYSTEM_VERSION 8.0)

set(PPC_PREFIX /opt/ppc-modern/bin/powerpc-apple-darwin9-)
set(CMAKE_C_COMPILER   ${PPC_PREFIX}gcc)
set(CMAKE_CXX_COMPILER ${PPC_PREFIX}g++)
set(CMAKE_AR           ${PPC_PREFIX}ar CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB       ${PPC_PREFIX}ranlib CACHE FILEPATH "" FORCE)
set(CMAKE_INSTALL_NAME_TOOL ${PPC_PREFIX}install_name_tool CACHE FILEPATH "" FORCE)
set(CMAKE_OTOOL        ${PPC_PREFIX}otool CACHE FILEPATH "" FORCE)
set(CMAKE_NM           ${PPC_PREFIX}nm CACHE FILEPATH "" FORCE)
set(CMAKE_STRIP        ${PPC_PREFIX}strip CACHE FILEPATH "" FORCE)

set(CMAKE_OSX_SYSROOT /opt/ppc/SDKs/MacOSX10.5.sdk CACHE PATH "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.4 CACHE STRING "")  # override with -D for Leopard builds
# FSF GCC has no -arch flag; the CPU comes from -mcpu instead.
set(CMAKE_OSX_ARCHITECTURES "" CACHE STRING "" FORCE)

set(CMAKE_FIND_ROOT_PATH /opt/ppc/SDKs/MacOSX10.5.sdk /opt/ppc-modern/icu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# GCC 6's runtime is shared, as in Leopard WebKit: every image uses one
# libstdc++.6.dylib and one libgcc_s.1.dylib, bundled in the app's Frameworks
# folder (/opt/ppc-modern/runtime holds copies with those install names). A static
# runtime in each image breaks std::call_once and anything else built on
# emulated thread-local storage, whose state is per copy of libgcc. The GCC
# driver's own choices are no good here -- it wants SDK stubs that ld64 cannot
# read for 10.4 -- so the libraries are named explicitly. Static libgcc comes
# last, for the few helpers the shared one leaves out. -static-libgcc stays
# only to stop g++ adding crt3.o for 10.4 targets, which crashes ld64.
#
# The load commands modern ld64 adds by default (function starts, data in
# code, version minimum, source version) are dropped: Leopard's gdb, otool
# and install_name_tool cannot parse binaries that carry them.
#
# Code bigger than PowerPC's branch reach (WebCore is about 30MB) links only
# because ld64 inserts branch islands, and it does so within one section.
# GCC puts cold code and static initializers in sections of their own
# (__text_cold, __text_startup), whatever the optimization flags say, so
# those are folded into __text.
set(PPC_RUNTIME /opt/ppc-modern/runtime)
set(PPC_LINK_FLAGS "-nodefaultlibs -static-libgcc -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version")
foreach (_section __text_cold __text_startup __text_exit __text_hot)
    set(PPC_LINK_FLAGS "${PPC_LINK_FLAGS} -Wl,-rename_section,__TEXT,${_section},__TEXT,__text")
endforeach ()
set(CMAKE_EXE_LINKER_FLAGS_INIT    "${PPC_LINK_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${PPC_LINK_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${PPC_LINK_FLAGS}")
# libatomic: 32-bit PowerPC has no 64-bit atomic instruction, and WebKit's
# 64-bit atomics become calls into it.
set(CMAKE_C_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libatomic.1.dylib ${PPC_RUNTIME}/libgcc_s.1.dylib -lgcc -lSystem")
set(CMAKE_CXX_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libstdc++.6.dylib ${PPC_RUNTIME}/libatomic.1.dylib ${PPC_RUNTIME}/libgcc_s.1.dylib -lgcc -lSystem")

# WebKit 2.52 is C++23. GNU mode, as Apple's own build uses, since Leopard's
# headers hide some C99 functions in strict mode.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_EXTENSIONS ON)
