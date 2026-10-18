/* wdlexis+ : SecRandomCopyBytes via getentropy (libSystem, macOS >= 10.12). */
#include <stddef.h>
#include <unistd.h>
#include <sys/random.h>
#include "Security/SecRandom.h"
const SecRandomRef kSecRandomDefault = NULL;
int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes) {
  unsigned char *p = (unsigned char *)bytes;
  (void)rnd;
  while (count > 0) {
    size_t n = count > 256 ? 256 : count;
    if (getentropy(p, n) != 0) return -1;
    p += n; count -= n;
  }
  return 0;
}
