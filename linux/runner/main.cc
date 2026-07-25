#include "my_application.h"

int main(int argc, char** argv) {
  // Disable the glycin SVG sandboxed loader which crashes when bwrap
  // cannot fork (common on NixOS, Flatpak, sandboxed distros, and some
  // Wayland sessions). GTK falls back to the standard pixbuf loader.
  g_setenv("GDK_DISABLE_GLYCIN", "1", FALSE);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
