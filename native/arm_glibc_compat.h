#ifndef ARM_GLIBC_COMPAT_H
#define ARM_GLIBC_COMPAT_H

#ifndef __ASSEMBLER__
#include <features.h>
#undef __GLIBC_USE_ISOC23
#define __GLIBC_USE_ISOC23 0
#undef __GLIBC_USE_C23_STRTOL
#define __GLIBC_USE_C23_STRTOL 0

__asm__(".symver dlopen, dlopen@GLIBC_2.4");
__asm__(".symver dlsym, dlsym@GLIBC_2.4");
__asm__(".symver dlclose, dlclose@GLIBC_2.4");
__asm__(".symver dlerror, dlerror@GLIBC_2.4");
__asm__(".symver exp, exp@GLIBC_2.4");
__asm__(".symver log, log@GLIBC_2.4");
__asm__(".symver log2, log2@GLIBC_2.4");
__asm__(".symver pow, pow@GLIBC_2.4");
__asm__(".symver fmod, fmod@GLIBC_2.4");
__asm__(".symver __isoc99_sscanf, sscanf@GLIBC_2.4");
#endif

#endif
