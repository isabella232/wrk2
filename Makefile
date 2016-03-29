CFLAGS  := -std=c99 -Wall -O2 -D_REENTRANT
LIBS    := -lpthread -lm -lssl -lcrypto

TARGET  := $(shell uname -s | tr '[A-Z]' '[a-z]' 2>/dev/null || echo unknown)

ifeq ($(TARGET), sunos)
	CFLAGS += -D_PTHREADS -D_POSIX_C_SOURCE=200112L
	LIBS   += -lsocket
else ifeq ($(TARGET), darwin)
	LDFLAGS += -pagezero_size 10000 -image_base 100000000
else ifeq ($(TARGET), linux)
        CFLAGS  += -D_POSIX_C_SOURCE=200112L -D_BSD_SOURCE
	LIBS    += -ldl
	LDFLAGS += -Wl,-E
else ifeq ($(TARGET), freebsd)
	CFLAGS  += -D_DECLARE_C99_LDBL_MATH
	LDFLAGS += -Wl,-E
endif

SRC  := wrk.c net.c ssl.c aprintf.c stats.c script.c units.c \
		ae.c zmalloc.c http_parser.c tinymt64.c hdr_histogram.c
BIN  := wrk

ODIR := obj
OBJ  := $(patsubst %.c,$(ODIR)/%.o,$(SRC)) $(ODIR)/bytecode.o

LDIR     = deps/luajit/src
LIBS    := -lluajit $(LIBS)
CFLAGS  += -I$(LDIR) -I$(ODIR)/include
LDFLAGS += -L$(LDIR) -L$(ODIR)/lib
DEPS    := $(LDIR)/libluajit.a $(ODIR)/lib/libssl.a

all: $(BIN)

clean:
	$(RM) -rf $(BIN) obj/*
	@$(MAKE) -C deps/luajit clean

$(BIN): $(OBJ)
	@echo LINK $(BIN)
	@$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

$(OBJ): config.h Makefile $(DEPS) | $(ODIR)

$(ODIR):
	@mkdir -p $@

$(ODIR)/bytecode.o: src/wrk.lua
	@echo LUAJIT $<
	@$(SHELL) -c 'cd $(LDIR) && ./luajit -b $(CURDIR)/$< $(CURDIR)/$@'

$(ODIR)/%.o : %.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c -o $@ $<

# Dependencies

OPENSSL := openssl-1.0.2g

deps/$(OPENSSL).tar.gz:
	curl -L -o $@ https://www.openssl.org/source/$(OPENSSL).tar.gz
ifeq ($(TARGET), darwin)
	pushd deps && shasum -a 256 -c $(OPENSSL).tar.gz.sha256
else
	pushd deps && sha256sum $(OPENSSL).tar.gz.sha256
endif

OPENSSL_OPTS = no-shared no-ssl2 no-psk no-srp no-dtls no-idea --prefix=$(abspath $(ODIR))

$(ODIR)/$(OPENSSL): deps/$(OPENSSL).tar.gz | $(ODIR)
	@tar -C $(ODIR) -xf $<

$(LDIR)/libluajit.a:
	@echo Building LuaJIT...
	@$(MAKE) -C $(LDIR) BUILDMODE=static

$(ODIR)/lib/libssl.a: $(ODIR)/$(OPENSSL)
	@echo Building OpenSSL...
ifeq ($(TARGET), darwin)
	@$(SHELL) -c "cd $< && ./Configure $(OPENSSL_OPTS) darwin64-x86_64-cc"
else
	@$(SHELL) -c "cd $< && ./config $(OPENSSL_OPTS)"
endif
	@$(MAKE) -C $< depend install

.PHONY: all clean
.SUFFIXES:
.SUFFIXES: .c .o .lua

vpath %.c   src
vpath %.h   src
vpath %.lua scripts
