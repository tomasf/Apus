/* Picks FreeType's debug source for the platform being built for. The manifest can't make this
   choice, because it's evaluated on the machine doing the build, which breaks cross-compiling. */

#if defined( _WIN32 )
#include "../builds/windows/ftdebug.c"
#else
#include "../src/base/ftdebug.c"
#endif
