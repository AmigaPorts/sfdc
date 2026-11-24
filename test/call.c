/* A call through the inline macros of a function that takes a function
   pointer and a pointer to one: the register variables they declare must
   be valid C. */
#include <proto/test.h>

static VOID handler(VOID)
{
}

VOID set_handler(VOID)
{
    VOID (*old)();

    TestSetHandler(handler, &old);
}
