# Captain Polliwog - builds a Universal (PowerPC + Intel) app for Mac OS X 10.4+.
# Requires Xcode 2.5 (Tiger) or Xcode 3.1 (Leopard) with the 10.4u SDK.

APP_NAME = Captain Polliwog
EXEC     = CaptainPolliwog
VERSION  = 0.2

SDK       ?= /Developer/SDKs/MacOSX10.4u.sdk
# Static OpenSSL and libcurl, built per architecture by scripts/build-deps.sh.
DEPS_ROOT ?= $(HOME)/polliwog-deps
ARCHS   ?= ppc i386
CC       = gcc-4.0
BUILD    = build
APP      = $(BUILD)/$(APP_NAME).app

export MACOSX_DEPLOYMENT_TARGET = 10.4

SRCS    = $(wildcard src/*.m)
HEADERS = $(wildcard src/*.h)

CFLAGS  = -isysroot $(SDK) -Os -Wall -Wno-unused-parameter
# G3 baseline so one PowerPC build runs on every PowerPC Mac; tuned for G4 laptops.
CFLAGS_ppc  = -mcpu=G3 -mtune=G4
CFLAGS_i386 =
LDFLAGS = -isysroot $(SDK) -Wl,-syslibroot,$(SDK) -framework Cocoa -framework WebKit -framework ApplicationServices -framework CoreServices -framework SystemConfiguration -framework Security -framework AddressBook
DEPS_LIBS = libcurl.a libssl.a libcrypto.a libz.a

.PHONY: all app clean

# Must stay the first rule: make 3.80/3.81 treat the first target as the default.
all: app

# Written out per architecture rather than generated: make 3.80 on Tiger dies
# with "virtual memory exhausted" on the $(eval)/$(foreach) version of this.
OBJS_ppc  = $(patsubst src/%.m,$(BUILD)/ppc/%.o,$(SRCS))
OBJS_i386 = $(patsubst src/%.m,$(BUILD)/i386/%.o,$(SRCS))
DEPS_ppc  = $(patsubst %,$(DEPS_ROOT)/ppc/lib/%,$(DEPS_LIBS))
DEPS_i386 = $(patsubst %,$(DEPS_ROOT)/i386/lib/%,$(DEPS_LIBS))

$(BUILD)/ppc/%.o: src/%.m $(HEADERS)
	@mkdir -p $(BUILD)/ppc
	$(CC) -arch ppc $(CFLAGS) $(CFLAGS_ppc) -I$(DEPS_ROOT)/ppc/include -c $< -o $@

$(BUILD)/i386/%.o: src/%.m $(HEADERS)
	@mkdir -p $(BUILD)/i386
	$(CC) -arch i386 $(CFLAGS) $(CFLAGS_i386) -I$(DEPS_ROOT)/i386/include -c $< -o $@

$(BUILD)/ppc/$(EXEC): $(OBJS_ppc)
	$(CC) -arch ppc $(OBJS_ppc) $(DEPS_ppc) $(LDFLAGS) -o $@

$(BUILD)/i386/$(EXEC): $(OBJS_i386)
	$(CC) -arch i386 $(OBJS_i386) $(DEPS_i386) $(LDFLAGS) -o $@

ARCH_BINARIES = $(patsubst %,$(BUILD)/%/$(EXEC),$(ARCHS))

$(BUILD)/$(EXEC): $(ARCH_BINARIES)
	lipo -create $(ARCH_BINARIES) -output $@

app: $(BUILD)/$(EXEC) Resources/Info.plist Resources/CaptainPolliwog.icns Resources/start.html Resources/cacert.pem Resources/polyfills.js Resources/autofill.js
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp $(BUILD)/$(EXEC) "$(APP)/Contents/MacOS/$(EXEC)"
	@sed -e 's/@VERSION@/$(VERSION)/g' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	@printf 'APPLCPwg' > "$(APP)/Contents/PkgInfo"
	@cp Resources/start.html Resources/cacert.pem Resources/polyfills.js Resources/autofill.js Resources/CaptainPolliwog.icns "$(APP)/Contents/Resources/"
	@echo "Built $(APP) ($$(lipo -info $(BUILD)/$(EXEC) | sed 's/.*: //'))"

clean:
	rm -rf $(BUILD)
