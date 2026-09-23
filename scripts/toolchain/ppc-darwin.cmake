# CMake toolchain: cross-compiling for PowerPC Mac OS X from Linux.
# Installed as /opt/ppc/share/ppc-darwin.cmake by build-ppc-toolchain.sh.
# Built against the 10.5 SDK with a 10.4 deployment target, so Leopard-only
# functions are weakly linked and simply absent on Tiger.
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR ppc)  # the name WebKit CMake recognises
set(CMAKE_SYSTEM_VERSION 8.0)

# Which compiler builds this. The default is the GCC 6.5 that Leopard
# WebKit's port was written for; TOOLCHAIN=/opt/ppc-modern in the
# environment selects the GCC 14 built for the 2.52 port instead, which
# knows this processor far better than 2015's compiler did. Each has its own
# runtime libraries, and an image must not see two of them.
if (DEFINED ENV{PPC_TOOLCHAIN})
    set(PPC_ROOT $ENV{PPC_TOOLCHAIN})
else ()
    set(PPC_ROOT /opt/ppc)
endif ()
set(PPC_PREFIX ${PPC_ROOT}/bin/powerpc-apple-darwin9-)
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

set(CMAKE_FIND_ROOT_PATH /opt/ppc/SDKs/MacOSX10.5.sdk /opt/ppc/icu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# GCC 6's runtime is shared, as in Leopard WebKit: every image uses one
# libstdc++.6.dylib and one libgcc_s.1.dylib, bundled in the app's Frameworks
# folder (/opt/ppc/runtime holds copies with those install names). A static
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
set(PPC_RUNTIME ${PPC_ROOT}/runtime)
set(PPC_LINK_FLAGS "-nodefaultlibs -static-libgcc -Wl,-no_function_starts,-no_data_in_code_info,-no_version_load_command,-no_source_version")
foreach (_section __text_cold __text_startup __text_exit __text_hot)
    set(PPC_LINK_FLAGS "${PPC_LINK_FLAGS} -Wl,-rename_section,__TEXT,${_section},__TEXT,__text")
endforeach ()
# Tiger: the stand-ins for what 10.4 has not got, ahead of the system
# frameworks so that those symbols bind here and everything else still comes
# from the system (engine/tiger-shim; webkit.sh sets this for 10.4).
if (DEFINED ENV{TIGER_SHIM})
    set(PPC_LINK_FLAGS "-L/opt/ppc/tiger-shim -lTigerShim ${PPC_LINK_FLAGS}")
endif ()

set(CMAKE_EXE_LINKER_FLAGS_INIT    "${PPC_LINK_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${PPC_LINK_FLAGS}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${PPC_LINK_FLAGS}")
# Thread-local storage is emulated on 10.5, and its state lives in whichever
# copy of the runtime an image happens to link. GCC 6's shared libgcc
# exports the two functions that reach it, so every image shares one copy.
# GCC 14 hides them, and each image would take its own from libgcc_eh.a -
# at which point std::call_once writes one copy and libstdc++ reads another,
# and the first thing the engine does on startup is jump to null.
# libemutls.1.dylib is those two functions and nothing else, listed ahead of
# the static libgcc so they bind there (build-modern-emutls.sh).
if (EXISTS ${PPC_RUNTIME}/libemutls.1.dylib)
    set(PPC_EMUTLS "${PPC_RUNTIME}/libemutls.1.dylib ")
else ()
    set(PPC_EMUTLS "")
endif ()
# PPC_STATIC_RUNTIME builds each image with its own copy of the C++ runtime.
# That is not how the engine ships - it breaks anything that shares a
# std::once_flag across two frameworks, because the emulated thread-local
# state is per copy - but it is self-contained, which is what a measurement
# of one compiler against another needs.
if (DEFINED ENV{PPC_STATIC_RUNTIME})
    set(PPC_LIBCXX "${PPC_ROOT}/powerpc-apple-darwin9/lib/libstdc++.a")
    set(CMAKE_C_STANDARD_LIBRARIES_INIT "-lgcc -lgcc_eh -lSystem")
    set(CMAKE_CXX_STANDARD_LIBRARIES_INIT "${PPC_LIBCXX} -lgcc -lgcc_eh -lSystem")
else ()
    set(CMAKE_C_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libgcc_s.1.dylib ${PPC_EMUTLS}-lgcc -lSystem")
    set(CMAKE_CXX_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libstdc++.6.dylib ${PPC_RUNTIME}/libgcc_s.1.dylib ${PPC_EMUTLS}-lgcc -lSystem")
endif ()

# libstdc++ tested for C99 TR1 math in strict mode, where the old math.h
# hides llround and friends; WebKit builds in GNU mode, where they exist.
set(CMAKE_CXX_FLAGS_INIT "-D_GLIBCXX_USE_C99_MATH_TR1=1")
