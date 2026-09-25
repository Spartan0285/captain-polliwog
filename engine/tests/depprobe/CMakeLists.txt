# Does WebKit 2.52 find the dependencies we cross-built, using its own
# Find modules and the same version floors OptionsGTK asks for? This is
# the dependency phase's exit exam: an archive that exists but that
# WebKit's finder cannot locate is not done.
cmake_minimum_required(VERSION 3.20)
project(depprobe C CXX)
list(APPEND CMAKE_MODULE_PATH "${WEBKIT_SOURCE}/Source/cmake")

set(_found "")
set(_missing "")

macro(probe name)
    find_package(${name} ${ARGN})
    if (${name}_FOUND OR ${name}_found OR TARGET ${name}::${name})
        list(APPEND _found "${name}")
    else ()
        list(APPEND _missing "${name}")
    endif ()
endmacro()

probe(Cairo 1.16.0)
probe(Fontconfig 2.13.0)
probe(Freetype 2.9.0)
probe(HarfBuzz 2.7.4 COMPONENTS ICU)
probe(JPEG)
probe(PNG)
probe(WebP COMPONENTS demux)
probe(LibXml2)
probe(SQLite3)
probe(ZLIB)
probe(LibGcrypt 1.7.0)
probe(Tasn1)
probe(ICU COMPONENTS data i18n uc)

message(STATUS "FOUND:   ${_found}")
message(STATUS "MISSING: ${_missing}")
