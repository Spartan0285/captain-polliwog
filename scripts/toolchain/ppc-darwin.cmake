# CMake toolchain: cross-compiling for PowerPC Mac OS X from Linux.
# Installed as /opt/ppc/share/ppc-darwin.cmake by build-ppc-toolchain.sh.
# Built against the 10.5 SDK with a 10.4 deployment target, so Leopard-only
# functions are weakly linked and simply absent on Tiger.
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR ppc)  # the name WebKit CMake recognises
set(CMAKE_SYSTEM_VERSION 8.0)

set(PPC_PREFIX /opt/ppc/bin/powerpc-apple-darwin9-)
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
set(PPC_RUNTIME /opt/ppc/runtime)
set(CMAKE_EXE_LINKER_FLAGS_INIT    "-nodefaultlibs -static-libgcc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-nodefaultlibs -static-libgcc")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-nodefaultlibs -static-libgcc")
set(CMAKE_C_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libgcc_s.1.dylib -lgcc -lSystem")
set(CMAKE_CXX_STANDARD_LIBRARIES_INIT "${PPC_RUNTIME}/libstdc++.6.dylib ${PPC_RUNTIME}/libgcc_s.1.dylib -lgcc -lSystem")

# libstdc++ tested for C99 TR1 math in strict mode, where the old math.h
# hides llround and friends; WebKit builds in GNU mode, where they exist.
set(CMAKE_CXX_FLAGS_INIT "-D_GLIBCXX_USE_C99_MATH_TR1=1")
