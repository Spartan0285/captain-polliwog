# Captain Polliwog - builds a Universal (PowerPC + Intel) app for Mac OS X 10.4+.
# Requires Xcode 2.5 (Tiger) or Xcode 3.1 (Leopard) with the 10.4u SDK.

APP_NAME = Captain Polliwog
EXEC     = CaptainPolliwog
VERSION  = 0.1

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
LDFLAGS = -isysroot $(SDK) -Wl,-syslibroot,$(SDK) -framework Cocoa -framework WebKit
DEPS_LIBS = libcurl.a libssl.a libcrypto.a

.PHONY: all app clean

# Must stay the first rule: make 3.80/3.81 treat the first target as the default.
all: app

define ARCH_RULES
OBJS_$(1) = $$(patsubst src/%.m,$(BUILD)/$(1)/%.o,$(SRCS))

$(BUILD)/$(1)/%.o: src/%.m $(HEADERS)
	@mkdir -p $(BUILD)/$(1)
	$(CC) -arch $(1) $(CFLAGS) $(CFLAGS_$(1)) -I$(DEPS_ROOT)/$(1)/include -c $$< -o $$@

$(BUILD)/$(1)/$(EXEC): $$(OBJS_$(1))
	$(CC) -arch $(1) $$^ $(patsubst %,$(DEPS_ROOT)/$(1)/lib/%,$(DEPS_LIBS)) -lz $(LDFLAGS) -o $$@
endef

$(foreach arch,$(ARCHS),$(eval $(call ARCH_RULES,$(arch))))

$(BUILD)/$(EXEC): $(foreach arch,$(ARCHS),$(BUILD)/$(arch)/$(EXEC))
	lipo -create $^ -output $@

app: $(BUILD)/$(EXEC) Resources/Info.plist Resources/start.html Resources/cacert.pem
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	@cp $(BUILD)/$(EXEC) "$(APP)/Contents/MacOS/$(EXEC)"
	@sed -e 's/@VERSION@/$(VERSION)/g' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	@printf 'APPLCPwg' > "$(APP)/Contents/PkgInfo"
	@cp Resources/start.html Resources/cacert.pem "$(APP)/Contents/Resources/"
	@echo "Built $(APP) ($$(lipo -info $(BUILD)/$(EXEC) | sed 's/.*: //'))"

clean:
	rm -rf $(BUILD)
