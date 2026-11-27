
### Class Macro68k: Implements m68k-only features for macro files #############

BEGIN {
    package MacroVBCC68k;
    use vars qw(@ISA);
    @ISA = qw( Macro );

    sub new {
      my $proto  = shift;
      my $class  = ref($proto) || $proto;
      my $self   = $class->SUPER::new( @_ );
      bless ($self, $class);
      return $self;
    }
    sub function {
      my $self  = shift;
      my %params = @_;
      my $prototype = $params{'prototype'};
      my $sfd       = $self->{SFD};
      my $regswap = "";
      my $function_start = $$prototype{'return'} ." __" . $$prototype{'funcname'} . "(__reg(\"a6\") struct Library * ";
      my $function = $function_start;
      if ($$prototype{private})
      {
        return;
      }
      # Handle VarArgs functions
      if ($$prototype{'type'} eq 'varargs')
      {
        print "#if !defined(NO_INLINE_STDARG) && (__STDC__ == 1L) && (__STDC_VERSION__ >= 199901L)\n";
        my $stackpush = "";
        my $stackpop = "";
        # The macro takes the arguments before the last named one, which
        # comes with the variable ones
        my $last_stdarg = $$prototype{"numargs"} - 2;
        # The function gets the address of an array of arguments in a
        # register.  A printfcall such as Printf(format, ...) (d1,d2) has
        # a register for every argument, the "..." included, and the array
        # holds only the variable arguments.  A tagcall such as
        # NewObject(cl, Tag tag1, ...) (a0,a1) has one register fewer, and
        # the array starts with its last named argument, tag1.
        my $array_arg = ($$prototype{'subtype'} // '') eq 'printfcall' ?
            $$prototype{"numargs"} - 1 : $last_stdarg;
        for(my $arg = 0; $arg < $$prototype{"numargs"}; $arg++)
        {
          my $reg = $$prototype{'regs'}[$arg];
          my $type = $$prototype{'argtypes'}[$arg];
          $function .= ", ";
          if(defined $reg && $arg < $array_arg)
          {
            $function .= "__reg(\"" . $reg . "\") ";
          }
          if(defined $reg && $arg == $array_arg)
          {
            # The call clobbers d0, d1, a0 and a1 anyway, and restoring
            # d0 would lose the result; any other register is kept
            my $scratch = $reg =~ /^[ad][01]$/;
            my $offset = $scratch ? 0 : 4;
            if(!$scratch)
            {
              $stackpush = "\\tmove.l\\t" . $reg . ",-(a7)\\n";
              $stackpop = "\\n\\tmove.l\\t(a7)+," . $reg;
            }
            # lea only loads an address register
            if($reg =~ /^a/)
            {
              $stackpush .= "\\tlea\\t" . $offset . "(a7)," . $reg . "\\n";
            }
            else
            {
              $stackpush .= "\\tmove.l\\ta7," . $reg . "\\n";
              $stackpush .= "\\taddq.l\\t#" . $offset . "," . $reg . "\\n" if $offset;
            }
          }
          $function .= $$prototype{'args'}[$arg] . " ";
        }
        $function .= sprintf ") = \"%s\\tjsr\\t-%ld(a6)%s\";",$stackpush,$$prototype{"bias"},$stackpop;
        print "$function\n";

        print "#define $$prototype{'funcname'}(";
        for(my $arg = 0; $arg < $last_stdarg; $arg++)
        {
          print $$prototype{'argnames'}[$arg];
          if ($arg != ($$prototype{"numargs"} - 1))
          {
            print ", ";
          }
        }
        print "...) __$$prototype{'funcname'}(" . $sfd->{BaseName} . "Base";
        for(my $arg = 0; $arg < $last_stdarg; $arg++)
        {
          print ", ";
          print "(" . $$prototype{'argnames'}[$arg] . ")";
        }
        print ", __VA_ARGS__)\n";
        print "#endif\n\n";
        return;
      }
      for(my $arg = 0; $arg < $$prototype{"numargs"}; $arg++)
      {
        my $reg = $$prototype{'regs'}[$arg];
        my $type = $$prototype{'argtypes'}[$arg];
        # make sure registers are in dn/dn format (assumes they either occur in dn-dn or dn/dn depending on inopu sfd file formattng
        $reg =~ s/-/\//g;
        # check for some possible 64bit types and fix registers if possible
        # first verify that it's not pointer the regsister isn;t an adress register and a register pair
        # isn't already defined.
        if(($type !~ m/\*/) && ($reg !~ m/^a.*|^d\d\/d\d$/))
        {
          # check for common 64 bit types
          if(($type =~ m/int64/) || ($type =~ m/double/) || ($type =~ m/long\s*long/))
          {
            my $regnum = substr $reg, 1;
            $reg .= "/d" . ($regnum + 1);
          }
        }
        # if a register pair makde sure it's even aligned.
        if($reg =~ m/^d(\d)\/d\d$/)
        {
          my $regnum = $1;
          if($regnum % 2)
          {
            if($regswap ne "")
            {
              print STDERR "Can only handle 1 pair of misaligned registers in function " . $$prototype{'funcname'} ."\n";
              return;
            }
            # odd register so we need to do register swap
            $regnum--;
            $reg = "d" . ($regnum ) . "/d" . ($regnum + 1);
            $$prototype{'regs'}[$arg] = $reg;
            my $found = 0;
            for(my $i = 0; $i <  $$prototype{"numargs"}; $i++)
            {
              if($$prototype{'regs'}[$i] eq "d" . $regnum)
              {
                $found = 1;
                $$prototype{'regs'}[$i] = "d" . ($regnum + 2);
                last;
              }
            }
            if($found)
            {
              # reset the function and start loop again.
              $function = $function_start;
              $arg = -1;
              $regswap = "\\texg\\td" . ($regnum + 1). ",d" . ($regnum + 2) . "\\n\\texg\\td" . ($regnum) . ",d" . ($regnum + 1) . "\\n\\t";
              next;
            }
            else
            {
              print STDERR "Unable to wrangle registers for misaligned 64bit arg in function " . $$prototype{'funcname'} ."\n";
              return;
            }
          }
        }
        $function .= ", __reg(\"" . $reg . "\") " . $$prototype{'args'}[$arg] . " ";
      }
      $function .= sprintf ") = \"%s\\tjsr\\t-%ld(a6)\";",$regswap,$$prototype{"bias"};
      # check for return type of pointer to function
      if ($function =~ m/^(.*)\(\*\)\((.*?)\)(.*);$/)
      {
        my $type = $1;
        my $returnfunc = $2;
        my $func = $3;
        my ($funcbody,$funcasm) = split("=",$func);
        print "$type (*$funcbody)($returnfunc) = $funcasm;\n"
      }
      else
      {
        print "$function\n";
      }
      print "#define $$prototype{'funcname'}(";
      for(my $arg = 0; $arg < $$prototype{"numargs"}; $arg++)
      {
        print $$prototype{'argnames'}[$arg];
        if ($arg != ($$prototype{"numargs"} - 1))
        {
          print ", ";
        }
      }
      print ") __$$prototype{'funcname'}(" . $sfd->{BaseName} . "Base";
      for(my $arg = 0; $arg < $$prototype{"numargs"}; $arg++)
      {
        print ", ";
        print "(" . $$prototype{'argnames'}[$arg] . ")";
      }
      print ")\n\n";
    }
}
