#!/usr/bin/perl -w
#
#     fd2sfd - Convert an FD file and a clib file to an SFD file
#
#     This program is free software; you can redistribute it and/or
#     modify it under the terms of the GNU General Public License
#     as published by the Free Software Foundation; either version 2
#     of the License, or (at your option) any later version.

use strict;
use warnings;

sub usage {
    print STDERR
      "Usage: $0 [options] fd-file clib-file [[-o] output-file]\n" .
      "       $0 [options] --no-clib fd-file [[-o] output-file]\n" .
      "Options:\n" .
      "--no-clib\t\tNo clib file: every type is ULONG, for the files\n" .
      "\t\t\tthat have none (LVO and pragma files)\n" .
      "--quiet\t\t\tDon't display warnings\n" .
      "--version\t\tPrint version number and exit\n\n" .
      "A public function without a matching prototype is an error.\n";
    exit 1;
}

my ($fd, $clib, $output);
my $no_clib = 0;
my $quiet   = 0;

for (my $i = 0; $i <= $#ARGV; $i++) {
    my $arg = $ARGV[$i];

    if ($arg =~ /^-/) {
      if ($arg eq '-o') {
          usage () if $i == $#ARGV || defined $output;
          $i++;
          $output = $ARGV[$i] if $ARGV[$i] ne '-';
          next;
      }

      (my $option = $arg) =~ s/^--?//;

      if ($option eq 'quiet') {
          $quiet = 1;
      }
      elsif ($option eq 'no-clib') {
          $no_clib = 1;
      }
      elsif ($option eq 'strict') {
          # Always the case now
      }
      elsif ($option eq 'version') {
          print STDERR "fd2sfd version SFDC_VERSION (sfdc)\n";
          exit 0;
      }
      else {
          usage ();
      }
    }
    elsif (!defined $fd) {
      $fd = $arg;
    }
    elsif (!defined $clib && !$no_clib) {
      $clib = $arg;
    }
    elsif (!defined $output) {
      $output = $arg;
    }
    else {
      usage ();
    }
}

usage () if !defined $fd || (!defined $clib && !$no_clib);

my $text = ReadFD->new (fd => $fd, clib => $clib, quiet => $quiet)->convert ();
exit 1 if !defined $text;

if (defined $output) {
    open (my $fh, '>', $output) or die "$0: can't write $output: $!\n";
    print $fh $text;
    close ($fh) or die "$0: can't write $output: $!\n";
}
else {
    print $text;
}

### Class ReadFD: Make an SFD file of an FD file and its C prototypes ########
#
# The FD file has the offsets, the registers and the argument names; the
# clib file has the types, and the varargs versions and aliases of the
# functions. A public function without a matching prototype is an error.

BEGIN {
    package ReadFD;

    use strict;
    use warnings;

    # Library bases whose type is not struct Library
    my %basetypes = (
      'BattClockBase'         => 'Node',
      'BattMemBase'           => 'Node',
      'ConsoleDevice'         => 'Device',
      'DiskBase'              => 'DiskResource',
      'DOSBase'               => 'DosLibrary',
      'SysBase'               => 'ExecBase',
      'ExpansionBase'         => 'ExpansionBase',
      'GfxBase'               => 'GfxBase',
      'InputBase'             => 'Device',
      'IntuitionBase'         => 'IntuitionBase',
      'LocaleBase'            => 'LocaleBase',
      'MathIeeeDoubBasBase'   => 'MathIEEEBase',
      'MathIeeeDoubTransBase' => 'MathIEEEBase',
      'MathIeeeSingBasBase'   => 'MathIEEEBase',
      'MathIeeeSingTransBase' => 'MathIEEEBase',
      'MiscBase'              => 'Node',
      'PotgoBase'             => 'Node',
      'RamdriveDevice'        => 'Device',
      'RealTimeBase'          => 'RealTimeBase',
      'RexxSysBase'           => 'RxsLib',
      'TimerBase'             => 'Device',
      'UtilityBase'           => 'UtilityBase',
    );

    # Library bases of modules that are not libraries
    my %module_types = (
      map ({ $_ => 'class' } qw(ARexxBase DTClassBase RequesterBase
                                WindowBase)),
      map ({ $_ => 'device' } qw(AHIBase ConsoleDevice InputBase
                                 RamdriveDevice TimerBase)),
      map ({ $_ => 'gadget' } qw(BGUIPaletteBase ButtonBase CheckBoxBase
                                 ChooserBase ColorWheelBase ClickTabBase
                                 DateBrowserBase FuelGaugeBase GetFileBase
                                 GetFontBase GetScreenModeBase IntegerBase
                                 LayoutBase ListBrowserBase PaletteBase
                                 PopCycleBase RadioButtonBase ScrollerBase
                                 SliderBase SpaceBase SpeedBarBase StringBase
                                 TextEditorBase TextFieldBase VirtualBase)),
      map ({ $_ => 'image' } qw(BevelBase BitMapBase DrawListBase GlyphBase
                                LabelBase PenMapBase)),
      map ({ $_ => 'resource' } qw(BattClockBase BattMemBase CardResource
                                   DiskBase KeymapBase MiscBase PotgoBase)),
    );

    # Types passed in two data registers
    my $wide = qr/^(double|DOUBLE|QUAD|UQUAD|(unsigned )?long long)$/;

    sub new {
      my $proto  = shift;
      my %params = @_;
      my $class  = ref($proto) || $proto;
      my $self   = {
        fd     => $params{'fd'},
        clib   => $params{'clib'},
        quiet  => $params{'quiet'} || 0,
        errors => 0,
      };
      bless ($self, $class);
      return $self;
    }

    sub error {
      my ($self, $where, $msg) = @_;
      print STDERR "$where: error: $msg\n";
      $self->{errors}++;
    }

    sub warning {
      my ($self, $where, $msg) = @_;
      print STDERR "$where: warning: $msg\n" if !$self->{quiet};
    }

    sub slurp {
      my $name = shift;
      open (my $fh, '<:raw', $name) or return undef;
      local $/;
      my $text = <$fh>;
      close ($fh);
      $text =~ s/\r//g;
      return $text;
    }

    # Whitespace as in "struct Node **name"
    sub tidy {
      my $str = shift;
      $str =~ s/\s+/ /g;
      $str =~ s/^ | $//g;
      $str =~ s/ ?\* ?/*/g;
      $str =~ s/(\w)\*/$1 */g;
      $str =~ s/\( /(/g;
      $str =~ s/ ([),])/$1/g;
      $str =~ s/,(?! )/, /g;
      return $str;
    }

    # Split at the commas that are not inside parentheses
    sub split_args {
      my $str = shift;
      my @args;
      my $depth = 0;
      my $arg = '';

      foreach my $char (split //, $str) {
        $depth++ if $char eq '(';
        $depth-- if $char eq ')';
        if ($char eq ',' && !$depth) {
          push @args, $arg;
          $arg = '';
        }
        else {
          $arg .= $char;
        }
      }
      push @args, $arg if $arg =~ /\S/ || @args;
      return map { tidy ($_) } @args;
    }

    # The type of an argument declaration, with "%s" where its name goes,
    # and the name
    sub arg_type {
      my $arg = shift;

      return ('...', '') if $arg eq '...';

      # A pointer to a function; a const pointer is no different to callers
      return ("$1%s$3", $2)
        if $arg =~ /^(.*\(\*+)(?:(?:const|CONST|volatile) )?(\w*)(\).*)$/;

      # An array is a pointer
      $arg = "$1 *$2" if $arg =~ /^(.*?) ?(\w+)\[[^\]]*\]$/;

      # A name follows a type, which is more than "struct" and the like
      if ($arg =~ /^(.*[ *])(\w+)$/) {
        my ($type, $name) = ($1, $2);
        if ($type !~ /^(const |CONST )?(struct|union|enum) $/ &&
            $name !~ /^(char|short|int|long|signed|unsigned|float|double|void|const|volatile)$/) {
          $type =~ s/ $//;
          return ($type =~ /\*$/ ? "$type%s" : "$type %s", $name);
        }
      }
      return ($arg =~ /\*$/ ? "$arg%s" : "$arg %s", '');
    }

    # The prototypes of the clib file, by name
    sub read_clib {
      my $self = shift;
      my $file = $self->{clib};
      my $text = slurp ($file);

      if (!defined $text) {
        $self->error ($file, "can't read it");
        return;
      }

      # Comments and preprocessor lines, keeping the line numbers
      $text =~ s{/\*(.*?)\*/}{"\n" x ($1 =~ tr/\n//) || ' '}gse;
      $text =~ s{//[^\n]*}{}g;
      while ($text =~ /^[ \t]*#[ \t]*include[ \t]*([<"][^>"\n]+[>"])/mg) {
        my $inc = $1;
        push @{$self->{includes}}, $inc
          if $inc !~ m{^.(proto|pragmas?|inline|ppc\w*|stormprotos)/};
      }
      $text =~ s{^[ \t]*#(?:[^\n]*\\\n)*[^\n]*}{}mg;
      $text =~ s/\bextern\s*"C"\s*\{|[{}]/;/g;

      while ($text =~ /([^;]*);/g) {
        my $decl  = $1;
        my $start = $-[1];
        $start += length $1 if $decl =~ /^(\s+)/;
        my $line  = 1 + (substr ($text, 0, $start) =~ tr/\n//);

        $decl =~ s/__attribute__\s*\(\(.*?\)\)//gs;
        $decl = tidy ($decl);
        $decl =~ s/^extern //;

        next if $decl eq '';

        if ($decl =~ /^typedef /) {
          push @{$self->{typedefs}}, $decl =~ s/^typedef //r;
        }
        elsif ($decl =~ /^([^()]*[ *])(\w+) ?\((.*)\)$/) {
          my ($ret, $name, $args) = ($1, $2, $3);
          my @args = split_args ($args);
          @args = () if "@args" =~ /^(void|VOID)$/;
          my @split = map { [ arg_type ($_) ] } @args;

          $ret =~ s/ $//;
          $self->{protos}{$name} //= {
            ret   => $ret,
            types => [ map { $$_[0] } @split ],
            names => [ map { $$_[1] } @split ],
            where => "$file:$line",
          };
          push @{$self->{order}}, $name;
        }
      }
    }

    # The functions of the FD file, in order
    sub read_fd {
      my $self = shift;
      my $file = $self->{fd};
      my $text = slurp ($file);

      if (!defined $text) {
        $self->error ($file, "can't read it");
        return;
      }

      my $bias    = 30;
      my $private;
      my $comment = '';
      my $line    = 0;

      $self->{base} = '';

      foreach (split /\n/, $text) {
        $line++;
        my $where = "$file:$line";

        if (/^\s*$/) {
        }
        elsif (/^\*(.*)$/) {
          $comment .= "*$1\n";
        }
        elsif (/^##base\s+_?(\w+)\s*$/) {
          $self->{base} = $1;
        }
        elsif (/^##bias\s+(\d+)\s*$/) {
          $bias = $1;
        }
        elsif (/^##(public|private)\s*$/) {
          $private = $1 eq 'private';
        }
        elsif (/^##end\s*$/) {
          last;
        }
        # Some FD files end the line with a ';', as in a C declaration
        elsif (/^\s*(\w+)\s*\(([^()]*)\)\s*\(([^()]*)\)\s*;?\s*$/) {
          my ($name, $params, $regs) = ($1, $2, $3);

          push @{$self->{funcs}}, {
            name    => $name,
            params  => [ grep { $_ ne '' } map { s/^\s+|\s+$//gr } split (/,/, $params) ],
            regs    => [ map { lc } grep { $_ ne '' } split (/[\s,\/]+/, $regs) ],
            bias    => $bias,
            private => $private,
            comment => $comment,
            where   => $where,
          };
          $comment = '';
          $bias += 6;
        }
        else {
          $self->error ($where, "not an FD line: $_");
        }
      }
    }

    # The registers of the arguments: two for a wide type
    sub arg_regs {
      my ($self, $func, $types) = @_;
      my @regs = grep { !/^(base|sysv)$/ } @{$$func{'regs'}};
      my @flags = grep { /^(base|sysv)$/ } @{$$func{'regs'}};
      my @args;

      foreach my $reg (@regs) {
        if ($reg !~ /^[ad][0-7]$/) {
          $self->error ($$func{'where'}, "$reg is not a register");
          return undef;
        }
      }

      for my $i (0 .. $#{$$func{'params'}}) {
        my $type = $$types[$i] // '';
        (my $bare = $type) =~ s/ ?%s$//;
        $bare =~ s/^(const|CONST) //;

        if (!@regs && @flags) {
          push @args, '';
        }
        elsif ($bare =~ $wide && @regs - (@{$$func{'params'}} - $i) >= 1) {
          push @args, shift (@regs) . '-' . shift (@regs);
        }
        elsif (@regs) {
          push @args, shift @regs;
        }
        else {
          $self->error ($$func{'where'}, "$$func{'name'}: fewer registers " .
                        "than arguments");
          return undef;
        }
      }

      if (@regs) {
        $self->error ($$func{'where'}, "$$func{'name'}: more registers " .
                      "than arguments");
        return undef;
      }

      return join (',', @flags, grep { $_ ne '' } @args);
    }

    sub declaration {
      my ($ret, $name, $types, $names, $regs) = @_;
      my @args = map {
        $$types[$_] eq '...' ? '...' : sprintf ($$types[$_], $$names[$_] // '')
      } 0 .. $#$types;
      my $sep = $ret =~ /\*$/ ? '' : ' ';

      return "$ret$sep$name(" . join (', ', @args) . ") ($regs)\n";
    }

    # Return the SFD file as a string, or undef after errors
    sub convert {
      my $self = shift;

      $self->{protos}   = {};
      $self->{order}    = [];
      $self->{includes} = [];
      $self->{typedefs} = [];
      $self->{funcs}    = [];

      $self->read_fd ();
      $self->read_clib () if defined $self->{clib};

      my %in_fd = map { $$_{'name'} => $_ } @{$self->{funcs}};
      my $protos = $self->{protos};
      my %extra;

      # The clib functions that the FD file lacks: varargs versions and
      # aliases of the ones it has
      foreach my $name (@{$self->{order}}) {
        next if $in_fd{$name} || $extra{$name};

        my $proto = $$protos{$name};
        my @types = @{$$proto{'types'}};
        my $of;

        if (@types && $types[-1] eq '...') {
          (my $tags = $name) =~ s/Tags$//;
          ($of) = grep { $in_fd{$_} && $$protos{$_} }
            ("${name}A", "${name}Args", "V$name", "${tags}TagList",
             "${tags}A", $tags, $name =~ s/^([A-Z]+)/$1V/r,
             $name =~ s/s$/A/r);
          $extra{$name} = { type => 'varargs', of => $of } if $of;
        }
        else {
          # An alias takes the same arguments, or the first ones
          ($of) = grep {
            my $types = $$protos{$_} && $$protos{$_}{'types'};
            $in_fd{$_} && $types && @types <= @$types &&
              "@types" eq "@{$types}[0 .. $#types]";
          } ($name =~ /^(\w+)TagList$/, $name =~ /^(\w+)\d$/, "${name}TagList");
          $extra{$name} = { type => 'alias', of => $of } if $of;
        }

        $self->warning ($$proto{'where'}, "$name is not in the FD file")
          if !$of;
      }

      my $fd   = $self->{fd};
      my $base = $self->{base};
      my $out  = '';

      $out .= "* Converted by sfdc from $fd";
      $out .= defined $self->{clib} ? " and $self->{clib}.\n" : ".\n";

      if ($base ne '') {
        (my $libname = $fd) =~ s{.*/}{};
        $libname =~ s/\.fd$//i;
        my $type = $libname =~ s/_(gc|ic|cl)$//
          ? { gc => 'gadget', ic => 'image', cl => 'class' }->{$1}
          : $module_types{$base} // 'library';
        $libname =~ s/_lib$//;
        $libname = 'card' if $libname eq 'cardres';

        $out .= "==base _$base\n";
        $out .= "==basetype struct " . ($basetypes{$base} // 'Library') . " *\n";
        $out .= "==libname $libname.$type\n";
      }

      my %seen;
      foreach my $inc (@{$self->{includes}}, '<exec/types.h>', '<utility/tagitem.h>') {
        $out .= "==include $inc\n" if !$seen{$inc}++;
      }
      $out .= "==typedef $_\n" foreach @{$self->{typedefs}};

      my $bias    = -1;
      my $private = -1;

      foreach my $func (@{$self->{funcs}}) {
        my $name  = $$func{'name'};
        my $proto = $$protos{$name};
        my @names = @{$$func{'params'}};

        # Before ##public or ##private, a function is what the clib file
        # says: public if it has a prototype
        $$func{'private'} //= defined $self->{clib} && !$proto ? 1 : 0;

        if (!$proto && !$$func{'private'} && defined $self->{clib}) {
          $self->error ($$func{'where'}, "$name has no prototype");
          next;
        }

        # Private functions are left out of the headers, so their types
        # don't matter; without a clib file, no types do
        $proto //= { ret => 'ULONG', types => [ map { 'ULONG %s' } @names ] };

        if (@{$$proto{'types'}} != @names) {
          if ($$func{'private'}) {
            $proto = { ret => $$proto{'ret'}, types => [ map { 'ULONG %s' } @names ] };
          }
          else {
            $self->error ($$func{'where'}, "$name has " . @names .
                          " arguments, and " . @{$$proto{'types'}} .
                          " in $$proto{'where'}");
            next;
          }
        }

        my $regs = $self->arg_regs ($func, $$proto{'types'});
        next if !defined $regs;

        $out .= $$func{'comment'};
        $out .= "==bias $$func{'bias'}\n" if $$func{'bias'} != $bias;
        $out .= ($$func{'private'} ? "==private\n" : "==public\n")
          if $$func{'private'} != $private;
        $bias    = $$func{'bias'} + 6;
        $private = $$func{'private'};

        $out .= declaration ($$proto{'ret'}, $name, $$proto{'types'},
                             \@names, $regs);

        foreach my $other (grep { $extra{$_} && $extra{$_}{'of'} eq $name }
                           @{$self->{order}}) {
          my $types = $$protos{$other}{'types'};
          my @regs  = split (/,/, $regs);

          # An alias may take fewer arguments, in the first registers. The
          # arguments that a varargs version passes in an array keep their
          # names from the prototype.
          my @other = @names;
          if ($extra{$other}{'type'} eq 'alias') {
            splice (@regs, scalar @$types);
          }
          else {
            my @own = @{$$protos{$other}{'names'}};
            for my $i ($#names .. $#$types) {
              $other[$i] = $own[$i] if ($own[$i] // '') ne '';
            }
          }

          $out .= "==$extra{$other}{'type'}\n";
          $out .= declaration ($$protos{$other}{'ret'}, $other, $types,
                               \@other, join (',', @regs));
        }
      }

      $out .= "==end\n";

      return $self->{errors} ? undef : $out;
    }
}
