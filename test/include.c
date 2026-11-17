/* Including the headers without calling anything must not warn, e.g.
   about unused varargs wrappers (-Wunused-function), nor compile any
   wrapper, even at -O0. */
#include <proto/test.h>
