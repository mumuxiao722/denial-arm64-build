// Non-visual ABI/AOT and render-node graphics checks. No window or scanout.
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <gbm.h>
#include <gnu/libc-version.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "flutter_embedder.h"

static void fail(const char *message) {
  fprintf(stderr, "%s\n", message);
  exit(EXIT_FAILURE);
}

static void *symbol(void *library, const char *name) {
  void *result = dlsym(library, name);
  if (result == NULL) {
    fprintf(stderr, "missing %s: %s\n", name, dlerror());
    exit(EXIT_FAILURE);
  }
  return result;
}

static void print_maps(void) {
  FILE *maps = fopen("/proc/self/maps", "r");
  if (maps == NULL) fail("cannot read process maps");
  char *line = NULL;
  size_t capacity = 0;
  while (getline(&line, &capacity, maps) != -1) {
    if (strstr(line, ".so") != NULL) fputs(line, stdout);
  }
  free(line);
  fclose(maps);
}

int main(int argc, char **argv) {
  if (argc != 3 && argc != 4 && argc != 5)
    fail("usage: probe ENGINE_SO AOT_SO [RENDER_NODE | --driver DRIVER_SO]");
  if (argc == 5 && strcmp(argv[3], "--driver") != 0)
    fail("expected --driver DRIVER_SO");
  printf("loaded glibc: %s\n", gnu_get_libc_version());
  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (library == NULL) fail(dlerror());
  const char *extensions[] = {
      "DenialFlutterEngineRequestFrameForExternalTextures",
      "DenialFlutterEngineScheduleFrameForExternalTextures",
      "DenialFlutterEngineRenderOutputs",
      "DenialFlutterEngineSetRenderOutputs",
      "DenialFlutterEngineSetExternalTextureGlStateCallback",
      "DenialFlutterEngineSetExternalTexturePresentationCallback",
  };
  for (size_t i = 0; i < sizeof(extensions) / sizeof(extensions[0]); ++i)
    symbol(library, extensions[i]);
  FlutterEngineResult (*get_procs)(FlutterEngineProcTable *) =
      symbol(library, "FlutterEngineGetProcAddresses");
  FlutterEngineProcTable table = {0};
  table.struct_size = sizeof(table);
  if (get_procs(&table) != kSuccess) fail("Flutter proc table failed");
#define REQUIRE_PROC(name) \
  do { if (table.name == NULL) fail("missing Flutter proc: " #name); } while (0)
  REQUIRE_PROC(CreateAOTData);
  REQUIRE_PROC(CollectAOTData);
  REQUIRE_PROC(Run);
  REQUIRE_PROC(Shutdown);
  REQUIRE_PROC(SendWindowMetricsEvent);
  REQUIRE_PROC(SendPointerEvent);
  REQUIRE_PROC(SendKeyEvent);
  REQUIRE_PROC(SendPlatformMessage);
  REQUIRE_PROC(SendPlatformMessageResponse);
  REQUIRE_PROC(RegisterExternalTexture);
  REQUIRE_PROC(UnregisterExternalTexture);
  REQUIRE_PROC(MarkExternalTextureFrameAvailable);
  REQUIRE_PROC(OnVsync);
  REQUIRE_PROC(PostRenderThreadTask);
  REQUIRE_PROC(GetCurrentTime);
  REQUIRE_PROC(RunTask);
  REQUIRE_PROC(UpdateLocales);
  REQUIRE_PROC(RunsAOTCompiledDartCode);
  REQUIRE_PROC(NotifyDisplayUpdate);
  if (!table.RunsAOTCompiledDartCode()) fail("engine is not AOT");
  FlutterEngineAOTDataSource source = {0};
  source.type = kFlutterEngineAOTDataSourceTypeElfPath;
  source.elf_path = argv[2];
  FlutterEngineAOTData aot = NULL;
  if (table.CreateAOTData(&source, &aot) != kSuccess || aot == NULL)
    fail("AOT data loading failed");
  puts("Flutter and Denial ABI and AOT data loading: passed");

  if (argc == 5) {
    void *driver = dlopen(argv[4], RTLD_NOW | RTLD_LOCAL);
    if (driver == NULL) fail(dlerror());
    puts("Mesa driver loading in the engine process: passed");
    print_maps();
    dlclose(driver);
  }
  if (argc != 4) {
    if (table.CollectAOTData(aot) != kSuccess) fail("AOT data release failed");
    dlclose(library);
    puts("non-visual ABI/AOT probe: passed");
    return EXIT_SUCCESS;
  }

  int fd = open(argv[3], O_RDWR | O_CLOEXEC);
  if (fd < 0) { perror("open render node"); return EXIT_FAILURE; }
  struct gbm_device *gbm = gbm_create_device(fd);
  if (gbm == NULL) { perror("GBM backend initialization"); return EXIT_FAILURE; }
  EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
  EGLint major, minor;
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, &major, &minor))
    fail("EGL initialization failed");
  if (!eglBindAPI(EGL_OPENGL_ES_API)) fail("EGL API selection failed");
  const EGLint attributes[] = {EGL_SURFACE_TYPE, 0, EGL_RENDERABLE_TYPE,
                              EGL_OPENGL_ES3_BIT, EGL_NONE};
  EGLConfig config;
  EGLint count;
  if (!eglChooseConfig(display, attributes, &config, 1, &count) || count < 1)
    fail("no GLES 3 EGL configuration");
  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                                       context_attributes);
  if (context == EGL_NO_CONTEXT ||
      !eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context))
    fail("surfaceless GLES 3 context failed");
  printf("GBM backend: %s; EGL: %d.%d; GL renderer: %s\n",
         gbm_device_get_backend_name(gbm), major, minor, glGetString(GL_RENDERER));
  print_maps();
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  eglDestroyContext(display, context);
  eglTerminate(display);
  gbm_device_destroy(gbm);
  close(fd);
  if (table.CollectAOTData(aot) != kSuccess) fail("AOT data release failed");
  dlclose(library);
  puts("non-visual probe: passed");
  return EXIT_SUCCESS;
}
