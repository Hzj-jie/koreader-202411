#include <stddef.h>

extern void _init(void);

typedef void (*init_fn_t)(int, char **, char **);
extern init_fn_t __init_array_start[];
extern init_fn_t __init_array_end[];

static void compat_libc_csu_init(int argc, char **argv, char **envp) {
    _init();
    size_t count = (size_t)(__init_array_end - __init_array_start);
    for (size_t i = 0; i < count; i++) {
        __init_array_start[i](argc, argv, envp);
    }
}

extern int __libc_start_main_compat(
    int (*main)(int, char **, char **),
    int argc,
    char **ubp_av,
    void (*init)(int, char **, char **),
    void (*fini)(void),
    void (*rtld_fini)(void),
    void *stack_end);
__asm__(".symver __libc_start_main_compat, __libc_start_main@GLIBC_2.4");

int __wrap___libc_start_main(
    int (*main)(int, char **, char **),
    int argc,
    char **ubp_av,
    void (*init)(int, char **, char **),
    void (*fini)(void),
    void (*rtld_fini)(void),
    void *stack_end) {
    (void)init;
    return __libc_start_main_compat(
        main, argc, ubp_av,
        compat_libc_csu_init,
        fini, rtld_fini, stack_end);
}
