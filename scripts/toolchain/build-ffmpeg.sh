#!/bin/bash
# Builds FFmpeg for PowerPC into /opt/ppc/ffmpeg, for the browser's media
# decoding. Run inside the cross-build VM.
#
# Why, when QuickTime already decodes H.264: QuickTime 7's decoder is the
# slowest part of watching anything on a G4, and FFmpeg's PowerPC code is
# hand-written AltiVec - h264dsp, h264chroma, the IDCT, the loop filter, and
# swscale's YUV-to-RGB, which is the other half of the cost. VLC and MPlayer
# on these machines are fast for exactly this reason.
#
# Built as static libraries: there is one consumer, and a dylib would add a
# lazy stub to every call into the decoder's inner loops.
#
# Decoders are chosen rather than taking the lot. H.264 and AAC are what the
# web actually serves; VP8 and VP9 are here because nothing else on these
# machines can play them at all, even slowly, and because a WebM that plays
# badly beats one that does not play.
#
# No TLS and no https protocol: FFmpeg never opens a connection here. The
# browser hands it bytes it has already fetched, through its own networking.
set -e
export PATH=/opt/ppc/bin:$PATH
V=6.1.2
SHA256=3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38
P=/opt/ppc/ffmpeg

mkdir -p ~/src/deps && cd ~/src/deps
[ -f ffmpeg-$V.tar.xz ] || wget -q https://ffmpeg.org/releases/ffmpeg-$V.tar.xz
echo "$SHA256  ffmpeg-$V.tar.xz" | sha256sum -c

sudo rm -rf $P && sudo mkdir -p $P && sudo chown "$(id -u)" $P

rm -rf ffmpeg-$V && tar xJf ffmpeg-$V.tar.xz && cd ffmpeg-$V

# --cpu=g4 would be the honest name, but FFmpeg maps it to -mcpu=7450, which
# is what the rest of the engine is tuned for anyway.
./configure \
    --prefix=$P \
    --enable-cross-compile --arch=ppc --cpu=g4 --target-os=darwin \
    --cross-prefix=powerpc-apple-darwin9- --cc=powerpc-apple-darwin9-gcc \
    --extra-cflags="-mmacosx-version-min=10.4" \
    --extra-ldflags="-mmacosx-version-min=10.4" \
    --enable-static --disable-shared --enable-pic \
    --disable-programs --disable-doc --disable-avdevice --disable-network \
    --disable-everything \
    --enable-decoder=h264,aac,aac_latm,mp3,vp8,vp9,opus,vorbis,flac,pcm_s16le,pcm_s16be,pcm_u8 \
    --enable-demuxer=mov,matroska,webm_dash_manifest,mp3,aac,ogg,wav,flac \
    --enable-parser=h264,aac,aac_latm,vp8,vp9,opus,vorbis,mpegaudio \
    --enable-protocol=file,pipe \
    --enable-swscale --enable-swresample \
    --enable-altivec --disable-vsx --disable-power8 \
    --disable-debug --disable-iconv --disable-sdl2 --disable-xlib \
    --disable-zlib --disable-bzlib --disable-lzma

make -j8
make install
ls -la $P/lib
echo FFMPEG_DONE
