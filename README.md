# Lua 5.4.7 for SCO OpenServer 5

A working build of [Lua 5.4.7](https://www.lua.org/) (October 2024) for
**SCO OpenServer 5.0.7** — an operating system whose newest native compiler
is GCC 2.95.3 from 1999.

```
$ /tmp/lua -v
Lua 5.4.7  Copyright (C) 1994-2024 Lua.org, PUC-Rio
$ /tmp/lua -e 'print(math.maxinteger)'
9223372036854775807
```

Just want to run Lua on your SCO box? Skip to **[Install](#install)**.

## Why?

SCO OpenServer 5 has no native modern scripting language — Python and Perl
are stuck at versions from the early 2000s, and building anything newer
hits a wall because the entire userspace is frozen at SVR3.2-era APIs.
Lua is small and self-contained enough to cross-compile cleanly, giving
you a genuinely modern scripting language on a 1999-vintage runtime:
64-bit integers, closures, coroutines, GC, metatables, pattern matching,
the works.

## Install

> **Fresh SCO box?** Install [curl with TLS](https://github.com/tachytelic/curl-7.88.1-for-SCO-OpenServer-5)
> first — that's the only file that needs to be transferred via `scp`.
> After that, every release on tachytelic/* (including this one) fetches
> over HTTPS from GitHub.

Fetch the binary directly on the SCO box:

```sh
# On the SCO box (assumes curl-with-TLS is installed — see curl-sco):
curl -LO https://github.com/tachytelic/Lua-5.4.7-for-SCO-OpenServer-5/releases/download/v1.0.0/lua
chmod +x lua
mv lua /usr/local/bin/lua
lua -v
```

The binary is about 320 KB, dynamically linked against `/usr/lib/libc.so.1`
and `/usr/lib/libm.so.1` (both are part of every SCO 5.0.7 install). No
other dependencies.

## Verify it works

`test_thorough.lua` in this repo is a 65-test functional suite covering
integers (64-bit), floats, strings, tables, closures, metatables,
coroutines, error handling, and the math/os/io libraries:

```bash
scp test_thorough.lua root@your-sco-host:/tmp/
ssh root@your-sco-host '/tmp/lua /tmp/test_thorough.lua'
```

Expected output ends with `=== RESULT: 65 passed, 0 failed ===`.

## What's included

**Works as documented in the [Lua 5.4 manual](https://www.lua.org/manual/5.4/):**

- Full Lua language: closures, coroutines, metatables, GC
- 64-bit integers (`math.maxinteger == 2^63-1`), IEEE-754 doubles
- `string` library — including `pack`/`unpack` and full pattern matching
- `table` library — including `sort`, `move`, `pack`/`unpack`
- `math` library — including `random` and all transcendentals
- `os.time`, `os.date`, `os.clock`, `os.getenv`, `os.remove`, `os.rename`
- `io` for reading/writing files and stdio
- `coroutine`, `utf8`, `debug`
- `require` for pure-Lua modules via `package.path`

**Not included** (not supported by SCO's runtime):

- `io.popen` and `os.execute` — would need `popen`/`system` and SCO's
  shell handling has too many sharp edges to bother
- `dlopen`-based C modules — SCO has no working `dlopen` from a
  modern-cross-compiled binary. Pure-Lua `require` still works fine.
- Multithreading — Lua itself is single-threaded; SCO's threading
  is also unusual enough that it wasn't worth wiring up

## Building from source

You probably don't need to do this — the `prebuilt/lua` binary in this
repo is what `build.sh` produces. But if you want to rebuild (e.g. with
different compile-time flags, or against a newer Lua), here's how.

### Requirements

A Linux build host with the `i686` cross-compiler:

```bash
sudo apt install gcc-13-i686-linux-gnu binutils-i686-linux-gnu python3 curl
```

You also need a **SCO sysroot** — a copy of `/usr/include/` and `/usr/lib/`
from a working SCO 5.0.7 install, accessible to the build host. By default
the build script looks in `/opt/sco-sysroot/`. Override with
`SCO_SYSROOT=/path/to/sysroot ./build.sh`.

The sysroot is the part most people don't have. There's no public source
for it — you need access to a SCO install (typical license seats include
the headers and libraries in `/usr/include` and `/usr/lib`) and copy
those two directories.

### Build

```bash
./build.sh
```

This downloads `lua-5.4.7.tar.gz` from lua.org, compiles all 33 source
files, links them, runs the ELF post-processor, and produces `lua_sco`.

## Why this is harder than it looks

SCO's runtime loader has three undocumented invariants that GNU `ld`
violates by default:

1. PT_PHDR must not include the ELF file header (don't use `FILEHDR PHDRS`).
2. PT_NOTE must be present with `p_filesz=0x1c` containing a specific
   28-byte SCO note.
3. There must be exactly 2 PT_LOAD segments where
   `LOAD[1].p_vaddr == PT_DYNAMIC.p_vaddr`.

Get any of these wrong and SCO's loader silently raises SIGFPE inside
its own stack-trace handler, which looks indistinguishable from a real
arithmetic exception in your code.

There are also two startup-time things SCO's normal `crt0.o` does that
external binaries can't trigger via the dynamic linker, so we do them
ourselves in a custom `_start`:

- `brk(_end)` to initialize the heap (otherwise `malloc` always fails)
- `atexit(_cleanup)` to register stdio buffer flushing (otherwise
  `printf` output disappears when `exit()` runs)

The `toolchain/` directory contains the linker script, custom `_start`,
ELF post-processor, and header shims that handle all of this — useful if
you want to cross-compile something else for SCO.

## Repository layout

```
prebuilt/
  lua                     Lua 5.4.7 binary, ready to scp to SCO  ← start here

test_thorough.lua         65-test functional suite

build.sh                  Top-level: downloads Lua source and builds lua_sco

toolchain/                SCO cross-compile infrastructure
  start_sco.s             Custom _start (brk init, atexit, no FPU init)
  sco.ld                  Linker script (PT_NOTE slot, .dynamic placement)
  sco_patch.py            ELF post-processor (PT_LOAD merge, SCO note)
  sco_compat.h            Header shims (ctype macros, _VA_LIST)
```

## License

The Lua language and the bundled `prebuilt/lua` binary are © 1994-2024
Lua.org, PUC-Rio, distributed under the [Lua MIT license](https://www.lua.org/license.html).
The source it was built from is unmodified upstream Lua 5.4.7.

The toolchain glue (`toolchain/`, `build.sh`, `test_thorough.lua`) is
released under the MIT license — see [LICENSE](LICENSE).

## See also

If you're keeping a SCO OpenServer 5 box alive, head over to
[tachytelic.net's SCO OpenServer 5 binaries page](https://tachytelic.net/2017/07/sco-openserver-5-binaries/)
— it collects other compiled software for the platform (bash, rsync,
tar, wget, lzop, …) along with notes on running these systems day to
day.

## Acknowledgements

Built and verified against SCO OpenServer 5.0.7 with the
`i686-linux-gnu` cross-compiler from Ubuntu 24.04. Thanks to the Lua
team for keeping the language tight enough to fit into a 1999-vintage
runtime envelope.
