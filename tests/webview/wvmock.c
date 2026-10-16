/* CC BY-NC-SA 4.0 - jean-marc "jihem" quere 2026
 *
 * Bibliothèque webview FACTICE : implémente l'API C de webview/webview 0.12
 * (webview.h) utilisée par src/paquets/pkg_webview.nim, sans moteur web ni
 * affichage. Elle permet de tester le pont Lexis+ <-> JavaScript :
 *
 *   - chaque appel webview_* est écrit sur la sortie standard ([mock] ...) ;
 *   - webview_run() lit un scénario (variable WVMOCK_SCRIPT) dont chaque
 *     ligne simule un appel JavaScript d'une fonction liée :
 *         js <nom> <arguments JSON>       ex. : js total [2,3]
 *         fermer                          l'utilisateur ferme la fenêtre
 *         attendre <ms>                   pause (la file de dispatch est traitée)
 *         # commentaire
 *     La file de webview_dispatch est vidée avant chaque ligne ; la boucle
 *     s'arrête à la fin du scénario, sur « fermer » ou webview_terminate().
 *
 *   gcc -shared -fPIC -o webview.so tests/webview/wvmock.c
 *   WDLEXIS_WEBVIEW=$PWD/webview.so WVMOCK_SCRIPT=tests/webview/scenario.txt \
 *     ./wdlexisrt tests/webview/principal.prg
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif

typedef void (*bind_fn)(const char *id, const char *req, void *arg);
typedef void (*dispatch_fn)(void *w, void *arg);

typedef struct {
  unsigned int major, minor, patch;
  char version_number[32];
  char pre_release[48];
  char build_metadata[48];
} webview_version_info_t;

static const webview_version_info_t version_info = {0, 12, 0, "0.12.0", "-factice", ""};

typedef struct { char name[128]; bind_fn fn; void *arg; } binding;
typedef struct { dispatch_fn fn; void *arg; } task;

typedef struct {
  int terminated;
  int nbinds;
  binding binds[128];
  int ntasks;
  task tasks[1024];
  int ncalls;
} mockwv;

static int nwindows = 0;

static void out(const char *fmt, const char *s) {
  printf(fmt, s);
  fflush(stdout);
}

API void *webview_create(int debug, void *window) {
  (void)window;
  mockwv *w = calloc(1, sizeof(mockwv));
  nwindows++;
  printf("[mock] create debug=%d\n", debug);
  fflush(stdout);
  return w;
}

API int webview_destroy(void *w) {
  out("[mock] destroy%s\n", "");
  free(w);
  return 0;
}

API int webview_terminate(void *w) {
  ((mockwv *)w)->terminated = 1;
  out("[mock] terminate%s\n", "");
  return 0;
}

API int webview_dispatch(void *w, dispatch_fn fn, void *arg) {
  mockwv *m = w;
  if (m->ntasks < 1024) { m->tasks[m->ntasks].fn = fn; m->tasks[m->ntasks].arg = arg; m->ntasks++; }
  return 0;
}

static void run_tasks(mockwv *m) {
  while (m->ntasks > 0) {
    task t = m->tasks[0];
    memmove(m->tasks, m->tasks + 1, sizeof(task) * (m->ntasks - 1));
    m->ntasks--;
    t.fn(m, t.arg);
  }
}

API void *webview_get_window(void *w) { (void)w; return NULL; }
API void *webview_get_native_handle(void *w, int kind) { (void)w; (void)kind; return NULL; }

API int webview_set_title(void *w, const char *title) { (void)w; out("[mock] titre : %s\n", title); return 0; }

API int webview_set_size(void *w, int width, int height, int hints) {
  (void)w;
  printf("[mock] taille : %d x %d (indice %d)\n", width, height, hints);
  fflush(stdout);
  return 0;
}

API int webview_navigate(void *w, const char *url) { (void)w; out("[mock] naviguer : %s\n", url); return 0; }

API int webview_set_html(void *w, const char *html) {
  (void)w;
  out("[mock] html : %.60s\n", html);
  return 0;
}

API int webview_init(void *w, const char *js) {
  (void)w;
  /* le script d'aide window.lexis est long : on n'en affiche que la nature. */
  if (strstr(js, "window.lexis") && strstr(js, "__interne")) out("[mock] init : script window.lexis%s\n", "");
  else out("[mock] init : %s\n", js);
  return 0;
}

API int webview_eval(void *w, const char *js) { (void)w; out("[mock] eval : %s\n", js); return 0; }

API int webview_bind(void *w, const char *name, bind_fn fn, void *arg) {
  mockwv *m = w;
  for (int i = 0; i < m->nbinds; i++)
    if (strcmp(m->binds[i].name, name) == 0) return 1; /* WEBVIEW_ERROR_DUPLICATE */
  if (m->nbinds < 128) {
    snprintf(m->binds[m->nbinds].name, sizeof m->binds[0].name, "%s", name);
    m->binds[m->nbinds].fn = fn;
    m->binds[m->nbinds].arg = arg;
    m->nbinds++;
  }
  out("[mock] lier : %s\n", name);
  return 0;
}

API int webview_unbind(void *w, const char *name) {
  mockwv *m = w;
  for (int i = 0; i < m->nbinds; i++)
    if (strcmp(m->binds[i].name, name) == 0) {
      m->binds[i] = m->binds[m->nbinds - 1];
      m->nbinds--;
      out("[mock] delier : %s\n", name);
      return 0;
    }
  return 2; /* WEBVIEW_ERROR_NOT_FOUND */
}

API int webview_return(void *w, const char *id, int status, const char *result) {
  (void)w;
  printf("[mock] retour %s %s : %s\n", id, status == 0 ? "ok" : "ERREUR", result);
  fflush(stdout);
  return 0;
}

API const webview_version_info_t *webview_version(void) { return &version_info; }

API int webview_run(void *w) {
  mockwv *m = w;
  out("[mock] run%s\n", "");
  const char *path = getenv("WVMOCK_SCRIPT");
  FILE *f = path ? fopen(path, "r") : NULL;
  char line[8192];
  /* scénarios successifs, un par fenêtre : les blocs sont séparés par « --- ». */
  static long offset = 0;
  if (f) fseek(f, offset, SEEK_SET);
  int sep = 0;
  run_tasks(m);
  while (!m->terminated && f && fgets(line, sizeof line, f)) {
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = 0;
    if (strcmp(line, "---") == 0) { sep = 1; break; }
    if (n == 0 || line[0] == '#') continue;
    run_tasks(m);
    if (strncmp(line, "attendre ", 9) == 0) { /* laisse le temps à un autre fil (arrêt, dispatch) */
      long ms = atol(line + 9);
      for (long t = 0; t < ms && !m->terminated; t += 10) { usleep(10000); run_tasks(m); }
      continue;
    }
    if (strcmp(line, "fermer") == 0) { out("[mock] fenêtre fermée par l'utilisateur%s\n", ""); break; }
    if (strncmp(line, "js ", 3) == 0) {
      char *name = line + 3;
      char *req = strchr(name, ' ');
      if (!req) continue;
      *req++ = 0;
      binding *b = NULL;
      for (int i = 0; i < m->nbinds; i++)
        if (strcmp(m->binds[i].name, name) == 0) b = &m->binds[i];
      if (!b) { out("[mock] fonction non liée : %s\n", name); continue; }
      char id[32];
      snprintf(id, sizeof id, "m%d", ++m->ncalls);
      printf("[mock] js %s(%s) id=%s\n", name, req, id);
      fflush(stdout);
      b->fn(id, req, b->arg);
    }
  }
  run_tasks(m);
  /* fenêtre fermée avant la fin de son bloc : passer au bloc suivant. */
  while (!sep && f && fgets(line, sizeof line, f))
    if (strncmp(line, "---", 3) == 0) sep = 1;
  if (f) { offset = ftell(f); fclose(f); }
  out("[mock] fin de la boucle%s\n", "");
  return 0;
}
