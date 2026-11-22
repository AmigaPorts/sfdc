#!/usr/bin/perl -w
#
#     fd2pragma - fd2pragma's command line, for fd2sfd and sfdc
#
#     Writes the files of the fd2pragma SPECIAL types that sfdc has a mode
#     for, with the names fd2pragma gives them: fd2sfd converts an FD file
#     to an SFD file, which sfdc compiles.
#
#     This program is free software; you can redistribute it and/or
#     modify it under the terms of the GNU General Public License
#     as published by the Free Software Foundation; either version 2
#     of the License, or (at your option) any later version.

use strict;
use warnings;

use File::Basename;
use File::Copy;
use File::Spec;
use File::Temp;

# SPECIAL => [ sfdc options, output file name ]; %s is the short base name.
# No options: the SFD file itself.
my %specials = (
    2   => [ [ '--mode=pragmas' ], '%s_pragmas.h' ],
    3   => [ [ '--mode=pragmas' ], '%s_pragmas.h' ],
    6   => [ [ '--mode=pragmas' ], '%s_lib.h' ],
    10  => [ [ '--mode=stubs' ], '%s_cstub.h' ],
    20  => [ [ '--mode=lvo' ], '%s_lvo.i' ],
    21  => [ [ '--mode=lvo' ], '%s_lib.i' ],
    22  => [ [ '--mode=lvo' ], '%s_lvo.i' ],
    23  => [ [ '--mode=lvo' ], '%s_lib.i' ],
    70  => [ [ '--target=m68kvbcc-amigaos', '--mode=macros' ], '%s_protos.h' ],
    110 => [ [ '--mode=fd' ], '%s_lib.fd' ],
    111 => [ [ '--mode=clib' ], '%s_protos.h' ],
    112 => [ [], '%s_lib.sfd' ],
);
$specials{$_} = [ [ '--mode=proto' ], '%s.h' ] for 30 .. 39;
$specials{$_} = [ [ '--target=m68k-gcc-amigaos', '--mode=macros' ], '%s.h' ]
  for 40 .. 47;

# The modes that write C types, which only the clib file has
my %needs_types = map { $_ => 1 } (10, 30 .. 47, 70, 111, 112);

# fd2pragma's options that take a value, and its switches
my %valued = map { $_ => 1 } qw(
    infile from special mode to clib abi copyright header hunkname basename
    libtype libname priority prefix subprefix premacro
);
my %switches = map { $_ => 1 } qw(
    autoheader comment externc fpuonly newsyntax nofpu noppc noppcregname
    nosymbol onlycnames opt040 ppconly private section smallcode smalldata
    smalltypes sorted systemrelease usesyscall voidbase
);
my %short = (
    h => 'help', i => 'infile', s => 'special', m => 'mode', t => 'to',
    c => 'clib', a => 'abi', r => 'copyright', d => 'header', n => 'hunkname',
    b => 'basename', l => 'libtype', p => 'priority',
);

sub help {
    print "fd2pragma (sfdc SFDC_VERSION)\n" .
      "Usage: fd2pragma [INFILE|-i FILE] [SPECIAL|-s N] [CLIB|-c FILE] " .
      "[TO|-t DIR]\n\n" .
      "SPECIAL types written with sfdc:\n" .
      "    2, 3, 6 - SAS/C, DICE, Maxon, Storm and Aztec pragmas\n" .
      "         10 - C stub functions\n" .
      "     20..23 - assembler LVO files\n" .
      "     30..39 - proto file\n" .
      "     40..47 - GCC inline file\n" .
      "         70 - VBCC inline file\n" .
      "        110 - FD file\n" .
      "        111 - clib file\n" .
      "        112 - SFD file\n";
    exit 20;
}

# Run fd2sfd or sfdc, next to this script or else in the PATH
sub run {
    my $tool = shift;
    my $path = File::Spec->catfile (dirname ($0), $tool);

    if (!-f $path) {
      ($path) = grep { -f } map { File::Spec->catfile ($_, $tool) }
        File::Spec->path ();
    }
    if (!defined $path) {
      print STDERR "fd2pragma: $tool not found\n";
      exit 20;
    }

    system ($^X, $path, @_) == 0 or exit 20;
}

print STDERR "\nfd2pragma: WARNING: fd2pragma is deprecated and will be removed " .
  "from m68k-amigaos-gcc.\n\n" .
  "Convert each FD file to an SFD file once, and maintain that instead:\n" .
  "  fd2sfd fd/mylib_lib.fd clib/mylib_protos.h -o sfd/mylib_lib.sfd\n" .
  "Then generate the headers from it with sfdc:\n" .
  "  sfdc --target=m68k-gcc-amigaos --mode=macros -o inline/mylib.h sfd/mylib_lib.sfd\n" .
  "\nDetails: https://github.com/AmigaPorts/m68k-amigaos-gcc/pull/368\n\n";

# Both fd2pragma's Unix options (-s 40, --special=40) and its AmigaDOS
# keywords (SPECIAL 40, SPECIAL=40) are accepted
my %args;
my @ignored;

for (my $i = 0; $i <= $#ARGV; $i++) {
    my $arg = $ARGV[$i];
    my ($name, $value);

    if ($arg =~ /^--([a-z0-9]+)(?:=(.*))?$/i) {
      ($name, $value) = (lc $1, $2);
    }
    elsif ($arg =~ /^-([a-z])(.*)$/i && $short{lc $1}) {
      ($name, $value) = ($short{lc $1}, $2 eq '' ? undef : $2);
      $value =~ s/^=// if defined $value;
    }
    elsif ($arg =~ /^([a-z0-9]+)(?:=(.*))?$/i &&
           ($valued{lc $1} || $switches{lc $1}) &&
           (defined $2 || $switches{lc $1} || $i < $#ARGV)) {
      ($name, $value) = (lc $1, $2);
    }
    elsif (!defined $args{'infile'}) {
      ($name, $value) = ('infile', $arg);
    }
    else {
      help ();
    }

    $name = 'infile' if $name eq 'from';
    help () if $name eq 'help';

    if ($switches{$name}) {
      push @ignored, uc $name;
      next;
    }
    help () if !$valued{$name};

    if (!defined $value) {
      help () if $i == $#ARGV;
      $value = $ARGV[++$i];
    }
    $value =~ s/^"(.*)"$/$1/;

    $args{$name} = $value;
}

help () if !defined $args{'infile'};

print STDERR "fd2pragma: ignored: " . join (' ', sort @ignored) . "\n"
  if @ignored;
foreach my $name (qw(mode abi copyright header hunkname basename libtype
                     libname priority prefix subprefix premacro)) {
    print STDERR "fd2pragma: ignored: " . uc ($name) . "\n"
      if defined $args{$name};
}

my $special = $args{'special'} // 6;
$special = 6 if $special eq '0';

if ($special !~ /^\d+$/ || !$specials{$special}) {
    print STDERR "fd2pragma: SPECIAL $special has no equivalent in sfdc.\n";
    exit 20;
}

# The input file, named in full or without _lib.sfd or _lib.fd
my $infile = $args{'infile'};
if (!-f $infile) {
    foreach my $ext ('_lib.sfd', '_lib.fd') {
      if (-f "$infile$ext") {
          $infile .= $ext;
          last;
      }
    }
}
if (!-f $infile) {
    print STDERR "fd2pragma: Can't open file $infile.\n";
    exit 20;
}

my $clib = $args{'clib'};
if (defined $clib && !-f $clib && -f "${clib}_protos.h") {
    $clib .= '_protos.h';
}

# The short base name: the file name without _lib.sfd or _lib.fd, or else
# the library base without "Base"
my $base = basename ($infile);
if (!($base =~ s/_lib\.s?fd$//i)) {
    $base = '';
    open (my $fh, '<', $infile) or die;
    while (my $line = <$fh>) {
      if ($line =~ /^(##|==)base\s+_?(\w+?)(Base)?\s*$/) {
          $base = $2;
          last;
      }
    }
    close ($fh);
}
if ($base eq '') {
    print STDERR "fd2pragma: Can't find the library base name.\n";
    exit 20;
}

my ($options, $pattern) = @{$specials{$special}};
my $name = sprintf ($pattern, $base);
my $to   = $args{'to'} // '';
$to .= '/' if $to ne '' && $to !~ m{[:/]$};

my $result = $to . $name;
print "ResultFile: $result\n";

my $is_sfd = 0;
{
    open (my $fh, '<', $infile) or die;
    while (my $line = <$fh>) {
      if ($line =~ /^==/) {
          $is_sfd = 1;
          last;
      }
      last if $line =~ /^##/;
    }
    close ($fh);
}

# An FD file becomes an SFD file first
my $sfd = $infile;
my $tmp;
if (!$is_sfd) {
    if (!defined $clib && $needs_types{$special}) {
      print STDERR "fd2pragma: SPECIAL $special needs the types of a CLIB file.\n";
      exit 20;
    }

    $tmp = File::Temp->new (SUFFIX => '_lib.sfd');
    $sfd = $tmp->filename;
    run ('fd2sfd', $infile, defined $clib ? $clib : '--no-clib', '-o', $sfd);
}

if (!@$options) {
    copy ($sfd, $result) or do {
      print STDERR "fd2pragma: Can't write $result.\n";
      exit 20;
    };
}
else {
    run ('sfdc', '--quiet', @$options, "--output=$result", $sfd);
}
