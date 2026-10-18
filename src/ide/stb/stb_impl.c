/* CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
   wdlexis+ : implémentation des bibliothèques stb (domaine public / MIT,
   Sean Barrett et contributeurs, voir LICENCES/stb.txt) utilisées par l'atelier :
   lecture d'images (PNG, JPEG, BMP, GIF, TGA), redimensionnement, écriture PNG
   et compression zlib (archives zip / tar.gz des distributions). */
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STBIW_ZLIB_LEVEL_DEFAULT 8
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize2.h"

/* libération des tampons alloués par stb (malloc). */
void wdlx_stb_free(void *p) { free(p); }

/* niveau de compression des PNG produits (icônes). */
void wdlx_stb_png_level(int level) { stbi_write_png_compression_level = level; }
