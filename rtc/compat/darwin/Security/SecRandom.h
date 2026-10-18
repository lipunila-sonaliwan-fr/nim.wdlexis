/* wdlexis+ : SecRandom.h minimal (implémenté par getentropy, sans Security.framework). */
#ifndef WDLX_SECRANDOM_H
#define WDLX_SECRANDOM_H
#include <stddef.h>
typedef const struct __SecRandom *SecRandomRef;
extern const SecRandomRef kSecRandomDefault;
int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes);
#endif
