#!/bin/bash
# Cross-compile Lua 5.4.7 for SCO OpenServer 5.
#
# Usage: ./build.sh
#   - Downloads lua-5.4.7.tar.gz if not present.
#   - Builds the lua interpreter using the SCO cross-toolchain in toolchain/.
#   - Output: lua_sco (~320 KB, dynamically linked against SCO's libc.so.1)
#
# Required tools on the build host (Ubuntu 22.04 / 24.04):
#   sudo apt install gcc-13-i686-linux-gnu binutils-i686-linux-gnu \
#                    python3 curl
#
# Required env: SCO_SYSROOT must point at a copy of /usr/include and
# /usr/lib/ from a working SCO OpenServer 5.0.7 install. Default is
# /opt/sco-sysroot. Override with `SCO_SYSROOT=/path/to/sysroot ./build.sh`.

set -e

SCO_SYSROOT="${SCO_SYSROOT:-/opt/sco-sysroot}"
GCC_INCL="${GCC_INCL:-/usr/lib/gcc-cross/i686-linux-gnu/13/include}"
LIBGCC="${LIBGCC:-/usr/lib/gcc-cross/i686-linux-gnu/13/libgcc.a}"
LUA_VERSION="${LUA_VERSION:-5.4.7}"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN="$REPO_ROOT/toolchain"

if [ ! -f "$SCO_SYSROOT/usr/lib/libc.so.1" ]; then
    echo "ERROR: SCO sysroot not found at $SCO_SYSROOT" >&2
    echo "Set SCO_SYSROOT to point at your SCO OpenServer 5 sysroot." >&2
    exit 1
fi

if [ ! -f "$LIBGCC" ]; then
    echo "ERROR: cross libgcc.a not found at $LIBGCC" >&2
    echo "Install with: sudo apt install gcc-13-i686-linux-gnu" >&2
    exit 1
fi

# Fetch Lua source from lua.org if not already present
if [ ! -d "lua-$LUA_VERSION" ]; then
    echo "  GET  lua-$LUA_VERSION.tar.gz"
    curl -sLO "https://www.lua.org/ftp/lua-$LUA_VERSION.tar.gz"
    tar xzf "lua-$LUA_VERSION.tar.gz"
fi

LUA_SRC="lua-$LUA_VERSION/src"
mkdir -p obj

# Compile flags. Notes:
#   -include sco_compat.h    : undef ctype macros and fix _VA_LIST clash
#   -fno-stack-protector     : SCO libc has no __stack_chk_fail_local
#   -nostdinc                : don't pull in glibc headers
#   No LUA_USE_C89           : would force 32-bit long ints on i386
#   No LUA_USE_LINUX/POSIX   : would enable popen, dlopen, signal stuff
#                              that doesn't work on SCO
# Default Lua config gives 64-bit long-long ints, doubles, ANSI runtime.
CFLAGS="-m32 -O2 -fno-stack-protector \
  -include $TOOLCHAIN/sco_compat.h \
  -nostdinc -I$GCC_INCL -I$LUA_SRC -I$SCO_SYSROOT/usr/include \
  -Wno-builtin-declaration-mismatch \
  -Wno-deprecated-declarations"

# Assemble custom _start (idempotent — only rebuild if .s changed)
if [ ! -f obj/start_sco.o ] || [ "$TOOLCHAIN/start_sco.s" -nt obj/start_sco.o ]; then
    echo "  AS   start_sco.s"
    i686-linux-gnu-as --32 -o obj/start_sco.o "$TOOLCHAIN/start_sco.s"
fi

# Lua sources for the interpreter (luac.c is a separate program)
LUA_OBJS=""
for src in lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject \
           lopcodes lparser lstate lstring ltable ltm lundump lvm lzio \
           lauxlib lbaselib lcorolib ldblib liolib lmathlib loadlib loslib \
           lstrlib ltablib lutf8lib linit lua; do
    obj="obj/$src.o"
    LUA_OBJS="$LUA_OBJS $obj"
    if [ "$LUA_SRC/$src.c" -nt "$obj" ] || [ ! -f "$obj" ]; then
        echo "  CC   $src.c"
        i686-linux-gnu-gcc $CFLAGS -c "$LUA_SRC/$src.c" -o "$obj"
    fi
done

echo "  LD   lua_base"
i686-linux-gnu-ld -m elf_i386 -T "$TOOLCHAIN/sco.ld" \
    -dynamic-linker /usr/lib/libc.so.1 \
    -o obj/lua_base \
    obj/start_sco.o $LUA_OBJS \
    "$SCO_SYSROOT/usr/lib/libc.so.1" "$SCO_SYSROOT/usr/lib/libm.so" "$LIBGCC" \
    --hash-style=sysv --build-id=none --no-pie

echo "  PATCH lua_sco"
python3 "$TOOLCHAIN/sco_patch.py" obj/lua_base lua_sco > /dev/null

echo
echo "Built: lua_sco ($(wc -c < lua_sco) bytes)"
echo
echo "Copy to your SCO box:"
echo "  scp lua_sco root@your-sco-host:/tmp/lua"
echo "Then on SCO:"
echo "  chmod +x /tmp/lua && /tmp/lua -v"
echo "  /tmp/lua test_thorough.lua    # run the 65-test suite"
