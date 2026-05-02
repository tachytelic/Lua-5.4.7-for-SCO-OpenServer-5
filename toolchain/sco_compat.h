#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
/* GCC stdarg.h first, then define _VA_LIST so SCO stdio.h doesn't redefine va_list */
#include <stdarg.h>
#define _VA_LIST va_list
/* Include ctype.h then undefine SCO macros that reference __ctype2 (internal,
   non-exported libc symbol). The actual functions ARE exported from libc.so.1. */
#include <ctype.h>
#undef isalpha
#undef isdigit
#undef isalnum
#undef isupper
#undef islower
#undef isspace
#undef isprint
#undef ispunct
#undef iscntrl
#undef isgraph
#undef isxdigit
#undef toupper
#undef tolower
