# Versioning
m4_define([v_maj], [1])
m4_define([v_min], [15])
m4_define([project_version], [v_maj.v_min])

# Process this file with autoconf to produce a configure script.
AC_INIT(sfdc, [project_version], martin@blom.org)

# Information on the package
VERSION=[project_version]
DATE=2026-11-22
AC_SUBST(VERSION)
AC_SUBST(DATE)

# Checks for programs.
AC_CHECK_PROGS([PERL], [perl])
AS_IF([test -z "$PERL"], [AC_MSG_ERROR([Perl is required])])
AC_CHECK_PROGS([POD2TEXT], [pod2text])
AS_IF([test -z "$POD2TEXT"], [AC_MSG_ERROR([pod2text is required])])
AC_CHECK_PROGS([POD2MAN], [pod2man])
AS_IF([test -z "$POD2MAN"], [AC_MSG_ERROR([pod2man is required])])
AC_PROG_INSTALL

# Checks for libraries.

# Checks for header files.

# Checks for typedefs and types

# Checks for structures

# Checks for compiler characteristics

# Checks for library functions.

AC_CONFIG_FILES([Makefile gg-sfdc.spec sfdc.readme])
AC_OUTPUT
