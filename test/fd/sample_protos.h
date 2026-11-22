#ifndef CLIB_SAMPLE_PROTOS_H
#define CLIB_SAMPLE_PROTOS_H

/*
**  The prototypes of sample_lib.fd, for the FD tests
*/

#include <exec/types.h>
#include <exec/lists.h>
#include <utility/tagitem.h>
#include <utility/hooks.h>
#include <proto/dummy.h>

typedef LONG SampleId;

LONG SampleFirst(LONG a);
LONG SampleAdd(LONG a, LONG b);
/* Not an alias of SampleAdd(): the arguments differ */
LONG SampleAdd2(struct List *list, LONG b);
struct Node *SampleFind(struct List *list, CONST_STRPTR name);
APTR SampleOpenA(CONST_STRPTR name, const struct TagItem *tags);
APTR SampleOpen(CONST_STRPTR name, Tag tag1, ...);
APTR SampleCreateTagList(struct TagItem *tags);
APTR SampleCreateTags(Tag, ...);
APTR SampleNew(struct TagItem *tags);
LONG VPrintf(CONST_STRPTR format, CONST APTR args);
LONG Printf(CONST_STRPTR format, ...);
ULONG SampleHook(ULONG (*hook)(struct Hook *, APTR), APTR data);
VOID SampleFree(APTR data, VOID (*CONST freefunc)());
double SampleScale(double value, LONG factor);
VOID SampleLater(VOID);
LONG System(CONST_STRPTR command, const struct TagItem *tags);
LONG SystemTagList(CONST_STRPTR command, const struct TagItem *tags);
LONG DoPkt(struct MsgPort *port, LONG action, LONG arg1, LONG arg2,
           LONG arg3, LONG arg4, LONG arg5);
LONG DoPkt0(struct MsgPort *port, LONG action);
/* LONG SampleCommented(LONG a); */
LONG SamplePrivate(LONG a);
UBYTE *SampleName(UBYTE buffer[32], SampleId id);

#endif /* CLIB_SAMPLE_PROTOS_H */
