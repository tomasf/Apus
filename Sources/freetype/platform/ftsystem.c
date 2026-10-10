/* Picks FreeType's system source for the platform being built for. The manifest can't make this
   choice, because it's evaluated on the machine doing the build, which breaks cross-compiling. */

#if defined( __APPLE__ )
#include "../builds/unix/ftsystem.c"
#elif defined( _WIN32 )
#include "../builds/windows/ftsystem.c"
#else
#include "../src/base/ftsystem.c"
#endif
