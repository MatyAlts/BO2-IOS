#if defined(__arm64__) && defined(__APPLE__)
.text
.p2align 2
.globl _probe_call_on_stack
_probe_call_on_stack:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    stp x21, x22, [sp, #-16]!
    stp x23, x24, [sp, #-16]!
    stp x25, x26, [sp, #-16]!
    mov x19, sp
    mov x20, x1
    mov x21, x2
    mov x22, x4
    mov x25, x5
    mov x23, #0x1357
    mov x24, #0x2468
    mov sp, x0
    mov w0, w21
    mov x1, x3
    mov x2, x22
    blr x20
    mov x9, #0x1357
    cmp x23, x9
    cset w10, eq
    mov x9, #0x2468
    cmp x24, x9
    cset w11, eq
    and w10, w10, w11
    str w10, [x25]
    mov sp, x19
    ldp x25, x26, [sp], #16
    ldp x23, x24, [sp], #16
    ldp x21, x22, [sp], #16
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
#endif
