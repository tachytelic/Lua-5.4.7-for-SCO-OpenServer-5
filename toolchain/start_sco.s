    /* Minimal _start for SCO OpenServer 5 cross-compiled binaries.
     *
     * SCO's standard crt0 calls __fpstart and _init_features_vector, which
     * are present in libc.so.1's .symtab but not exported to the dynamic
     * linker — external binaries cannot call them.
     *
     * The two things they do that we DO need:
     *   1. brk(_end) — initialize the heap break, otherwise sbrk(0)
     *      returns 0 and malloc() always fails.
     *   2. atexit(_cleanup) — register stdio cleanup so exit() flushes
     *      stdout. Without this, buffered output is lost when exit()
     *      runs (a common case: stdout block-buffered when not a tty).
     *
     * Both _cleanup and atexit ARE exported to the dynamic linker.
     */
    .section .text
    .globl _start
    .extern brk
    .extern atexit
    .extern _cleanup
    .extern main
    .extern exit
    .extern _end
_start:
    xorl  %ebp, %ebp
    movl  (%esp), %eax        /* argc */
    leal  4(%esp), %ecx        /* argv */
    leal  8(%esp,%eax,4), %edx /* envp */

    /* Save argc/argv/envp on the stack as the frame for main() */
    pushl %edx
    pushl %ecx
    pushl %eax

    /* Initialize the heap: brk(_end). The linker provides _end pointing past
     * .bss; this tells the kernel to set our break to that address so sbrk
     * (and therefore malloc) work. */
    pushl $_end
    call  brk
    addl  $4, %esp

    /* Register stdio cleanup so exit() flushes buffered output. */
    pushl $_cleanup
    call  atexit
    addl  $4, %esp

    call  main

    /* exit(main return value) */
    pushl %eax
    call  exit

    /* Should never reach here. SCO syscall convention is lcall $7,$0 not
     * Linux-style int $0x80, so we just halt. */
    hlt
