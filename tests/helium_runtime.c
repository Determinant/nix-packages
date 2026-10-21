/* Inspect the real executable's launcher environment without starting Helium. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

__attribute__((constructor)) static void check_runtime(void) {
  const char *target = getenv("HELIUM_RUNTIME_CHECK_TARGET");
  char executable[PATH_MAX];
  ssize_t length = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
  if (!target || length < 0)
    return;
  executable[length] = '\0';
  /* Shell/binary wrappers also inherit LD_PRELOAD. Wait for the real browser. */
  if (strcmp(executable, target) != 0)
    return;

  void *gtk = dlopen("libgtk-3.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (!gtk) {
    fprintf(stderr, "Helium cannot load its GTK printing dependency: %s\n", dlerror());
    _exit(1);
  }
  const char *symbols[] = {"gtk_print_job_new", "gtk_print_job_send"};
  for (size_t i = 0; i < sizeof(symbols) / sizeof(symbols[0]); ++i) {
    if (!dlsym(gtk, symbols[i])) {
      fprintf(stderr, "Helium GTK printing symbol %s is unavailable: %s\n",
              symbols[i], dlerror());
      _exit(1);
    }
  }

  puts("Helium: GTK library and printing entry points loaded through the launcher");
  fflush(stdout);
  _exit(0);
}
