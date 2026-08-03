BEGIN {
    package MacroGCC;
    use vars qw(@ISA);
    @ISA = qw( Macro );   # reuse ctor/header/footer from Macro

    sub rewrite_type_for_declaration {
        my ($type, $name) = @_;

        # Detect function pointer types: something like "ULONG (*)()"
        if ($type =~ /(.*)\(\s*\*\s*\)\s*(\(.*\))/) {
            my $ret  = $1;
            my $args = $2;
            return "${ret}(*${name})${args}";
        }

        # Normal type
        return "$type $name";
    }

    sub header {
      my $self = shift;
      my $sfd  = $self->{SFD};

      $self->SUPER::header (@_);

      if ($$sfd{'base'} ne '') {
          print "#ifndef $self->{BASE}\n";
          print "#define $self->{BASE} $$sfd{'base'}\n";
          print "#endif /* !$self->{BASE} */\n";
          print "\n";
      }
    }

    # Helper: Check if a function is varargs
    sub is_varargs_function {
        my ($self, $p) = @_;
        
        # Check for ==varargs directive
        return 1 if $$p{'varargs'};
        
        # Check for explicit "..."
        my @names = @{$$p{'___argnames'}};
        return 1 if (@names && $names[-1] eq '...');
        
        return 0;
    }

    # Helper: Clean parameter lists (remove "..." and fix corrupted names)
    sub clean_parameters {
        my ($self, $types_ref, $names_ref) = @_;
        my @types = @$types_ref;
        my @names = @$names_ref;
        
        # If the last type is '...' or last name is '...', remove it
        if (@types && $types[-1] eq '...') {
            pop @types;
            pop @names;
        }
        elsif (@names && $names[-1] eq '...') {
            pop @types;
            pop @names;
        }
        
        # Sometimes the parser creates a corrupted entry like "CONST_APTR ..., ..."
        # Check if any name is '...' and remove it
        for (my $i = 0; $i < @names; $i++) {
            if ($names[$i] eq '...') {
                splice(@types, $i, 1);
                splice(@names, $i, 1);
                last;
            }
        }
        
        return (\@types, \@names);
    }

    # Helper: Detect varargs pattern
    sub detect_varargs_pattern {
        my ($self, $p) = @_;
        my $fname = $$p{'funcname'};
        my @types = @{$$p{'argtypes'}};
        my @names = @{$$p{'___argnames'}};
        
        # Clean parameters first
        my ($clean_types, $clean_names) = $self->clean_parameters(\@types, \@names);
        @types = @$clean_types;
        @names = @$clean_names;
        
        # TagList pattern: function ends with "Tags"
        if ($fname =~ /Tags$/) {
            return 'taglist';
        }
        
        # Format string pattern: FPrintf, FWritef, Printf
        if ($fname =~ /^(FPrintf|FWritef|Printf)$/) {
            return 'format';
        }
        
        # Multi-arg pattern: DoPkt family
        if ($fname =~ /^DoPkt\d*$/) {
            return 'multi';
        }
        
        # Check if second argument is format string
        if (@types >= 2 && $types[1] =~ /CONST_STRPTR|format/i) {
            return 'format';
        }
        
        # Default to taglist
        return 'taglist';
    }

    # Generate TagList varargs helper
    sub generate_taglist_varargs {
        my ($self, %params) = @_;
        my $p = $params{'prototype'};
        my $fname = $$p{'funcname'};
        my $ret = $$p{'return'};
        my @types = @{$$p{'argtypes'}};
        my @names = @{$$p{'___argnames'}};
        
        # Clean parameters
        my ($clean_types, $clean_names) = $self->clean_parameters(\@types, \@names);
        @types = @$clean_types;
        @names = @$clean_names;
        
        my $fixed_count = scalar(@names);
        my $is_void = ($ret =~ /^(VOID|void)$/);
        
        # Derive TagList version
        my $taglist_fname = $fname;
        $taglist_fname =~ s/Tags$//;
        $taglist_fname .= 'TagList';
        
        # Emit static helper declaration
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", ";
        }
        print "...);\n\n";
        
        # Emit static helper definition
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", ...)\n{\n";
        
        my $last_fixed = $names[$fixed_count-1];
        print "    const ULONG *tags = &$last_fixed;\n";
        
        if ($is_void) {
            print "    $taglist_fname(";
        } else {
            print "    return $taglist_fname(";
        }
        
        for my $i (0 .. $fixed_count-2) {
            print "$names[$i]";
            print ", ";
        }
        print "(CONST struct TagItem *)tags);\n";
        print "}\n\n";
        
        # Emit macro wrapper
        print "#define $fname(";
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i], ";
        }
        print "...) __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i], ";
        }
        print "__VA_ARGS__)\n\n";
    }

    # Generate Format String varargs helper
    sub generate_format_varargs {
        my ($self, %params) = @_;
        my $p = $params{'prototype'};
        my $fname = $$p{'funcname'};
        my $ret = $$p{'return'};
        my @types = @{$$p{'argtypes'}};
        my @names = @{$$p{'___argnames'}};
        
        # Clean parameters - remove any "..." entries
        my ($clean_types, $clean_names) = $self->clean_parameters(\@types, \@names);
        @types = @$clean_types;
        @names = @$clean_names;
        
        my $fixed_count = scalar(@names);
        my $is_void = ($ret =~ /^(VOID|void)$/);
        
        # Derive V version name
        my $v_fname = "V$fname";
        
        # Emit helper declaration with actual parameter names
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", ...);\n\n";
        
        # Emit helper definition with actual parameter names
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", " 
        }
        print "...)\n{\n";
        
        # Get the last fixed parameter name
        my $last_fixed = $names[$fixed_count-1];
        
        # With __stdargs, all parameters are on the stack.
        # The address of the last fixed parameter + 1 gives us
        # the start of the varargs on the stack.
        print "    const void *args = (const void *)&$last_fixed + 1;\n";
        
        if ($is_void) {
            print "    $v_fname(";
        } else {
            print "    return $v_fname(";
        }
        
        # Call the V version with the actual parameter names
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", args);\n";
        print "}\n\n";
        
        # Emit macro wrapper with actual parameter names
        print "#define $fname(";
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i], ";
        }
        print "...) __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i], ";
        }
        print "__VA_ARGS__)\n\n";
    }

    # Generate Multi-Arg varargs helper (for DoPkt family)
    sub generate_multi_varargs {
        my ($self, %params) = @_;
        my $p = $params{'prototype'};
        my $fname = $$p{'funcname'};
        my $ret = $$p{'return'};
        my @types = @{$$p{'argtypes'}};
        my @names = @{$$p{'___argnames'}};
        
        # Clean parameters
        my ($clean_types, $clean_names) = $self->clean_parameters(\@types, \@names);
        @types = @$clean_types;
        @names = @$clean_names;
        
        my $fixed_count = scalar(@names);
        my $is_void = ($ret =~ /^(VOID|void)$/);

        # Emit helper declaration
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", ...);\n\n";
        
        # Emit helper definition
        print "static __stdargs $ret __${fname}_va(";
        for my $i (0 .. $fixed_count-1) {
            print "$types[$i] $names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", ...)\n{\n";
        
        print "    LONG args[5] = {0, 0, 0, 0, 0};\n";
        print "    int count = 0;\n";
        
        # Get the last fixed parameter
        my $last_fixed = $names[$fixed_count-1];
        my $last_type = $types[$fixed_count-1];
        
        print "    const LONG *argptr = (const LONG *)&$last_fixed + 1;\n";
        print "    \n";
        print "    while (count < 5 && argptr) {\n";
        print "        args[count++] = *argptr++;\n";
        print "    }\n";
        print "    \n";
        
        if ($is_void) {
            print "    DoPkt(";
        } else {
            print "    return DoPkt(";
        }
        
        for my $i (0 .. $fixed_count-1) {
            print "$names[$i]";
            print ", " if $i < $fixed_count-1;
        }
        print ", args[0], args[1], args[2], args[3], args[4]);\n";
        print "}\n\n";
    }

    # Generate aliases for a function
    sub generate_aliases {
        my ($self, %params) = @_;
        my $p = $params{'prototype'};
        my @aliases = @{$$p{'aliases'} // []};
        my $main_name = $$p{'funcname'};
        my $ret = $$p{'return'};
        
        return unless @aliases;
        
        foreach my $alias (@aliases) {
            my $alias_name = $$alias{'funcname'};
            my @alias_types = @{$$alias{'argtypes'}};
            my @alias_names = @{$$alias{'___argnames'}};
            my @alias_regs = @{$$alias{'regs'}};
            
            # Clean alias parameters too
            my ($clean_types, $clean_names) = $self->clean_parameters(\@alias_types, \@alias_names);
            @alias_types = @$clean_types;
            @alias_names = @$clean_names;
            
            # Create macro redirect
            print "#define $alias_name(";
            print join(", ", @alias_names);
            print ") $main_name(";
            print join(", ", @alias_names);
            print ")\n";
            
            # Create inline wrapper function
            print "static inline $ret __${alias_name}(";
            for my $i (0 .. $#alias_types) {
                my $decl = rewrite_type_for_declaration($alias_types[$i], $alias_names[$i]);
                print $decl;
                print ", " if $i < $#alias_types;
            }
            print ") {\n";
            print "    return $main_name(";
            print join(", ", @alias_names);
            print ");\n";
            print "}\n\n";
        }
    }

    sub function {
      my $self      = shift;
      my %params    = @_;
      my $p         = $params{'prototype'};
      my $sfd       = $self->{SFD};

      return if $p->{private};

      my $ret       = $$p{'return'};
      my @types     = @{$$p{'argtypes'}};
      my @names     = @{$$p{'___argnames'}};
      my @regs      = @{$$p{'regs'}};
      my $bias      = $$p{'bias'};
      my $is_void   = ($ret =~ /^(VOID|void)$/);
      my $fname     = $$p{'funcname'};

      # Check if this is a varargs function
      if ($self->is_varargs_function($p)) {
          my $pattern = $self->detect_varargs_pattern($p);
          
          if ($pattern eq 'taglist') {
              $self->generate_taglist_varargs(%params);
          } elsif ($pattern eq 'format') {
              $self->generate_format_varargs(%params);
          } elsif ($pattern eq 'multi') {
              $self->generate_multi_varargs(%params);
          } else {
              # Fallback to generic taglist
              $self->generate_taglist_varargs(%params);
          }
          
          # Generate aliases for varargs function
          $self->generate_aliases(%params);
          return;
      }

      # forced_a4 states:
      # 0 = normal mode (emit dual version if a4 used)
      # 1 = non-baserel version
      # 2 = baserel version (a4 <-> d6 swap)
      my $forced_a4 = $params{'forced_a4'} // 0;

      # detect if any arg is assigned to a5 / a4 in the SFD
      my $uses_a5 = 0;
      my $uses_a4 = 0;
      for my $r (@regs) {
          next unless defined $r && $r ne '';
          $uses_a5 = 1 if $r eq 'a5';
          $uses_a4 = 1 if $r eq 'a4';
      }

      # If a4 is used and we are in normal mode (forced_a4 == 0),
      # emit dual version guarded by __baserel__
      if ($uses_a4 && $forced_a4 == 0) {
          print "#ifndef __baserel__\n";
          $self->function(%params, forced_a4 => 1);
          print "#else\n";
          $self->function(%params, forced_a4 => 2);
          print "#endif /* __baserel__ */\n\n";
          return;
      }

      # Emit macro redirect
      print "#define $$p{'funcname'}(";
      print join(", ", @names);
      print ") __$$p{'funcname'}(";
      print join(", ", @names);
      print ")\n";

      # Emit static inline with prefixed name
      print "static inline $ret __$$p{'funcname'}(";
      for my $i (0 .. $#types) {
          my $decl = rewrite_type_for_declaration($types[$i], $names[$i]);
          print $decl;
          print ", " if $i < $#types;
      }
      print ") {\n";

      # return register (only for non-void)
      if (!$is_void) {
          print "  register $ret __v_ret __asm(\"d0\");\n";
      }

      # library base in a6
      print "  register void *const __v_base __asm(\"a6\") = $self->{BASE};\n";

      # bind args to their registers
      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';

          # remap special registers:
          # - a5 -> d7 (frame pointer preservation)
          # - a4 -> d6 only in forced_a4 == 2 (baserel version)
          my $bind_reg =
              ($r eq 'a5')               ? 'd7' :
              ($r eq 'a4' && $forced_a4 == 2) ? 'd6' :
                                                $r;

          my $decl = rewrite_type_for_declaration($types[$i], "__v$i");
          print "  register $decl __asm(\"$bind_reg\") = $names[$i];\n";
      }

      # build input constraints
      my @inputs;
      push @inputs, "\"a\"(__v_base)";

      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';

          # effective register (a5->d7, a4->d6 only in forced_a4 == 2)
          my $bind_reg =
              ($r eq 'a5')               ? 'd7' :
              ($r eq 'a4' && $forced_a4 == 2) ? 'd6' :
                                                $r;

          my $c =
              $bind_reg =~ /^a/  ? "a" :
              $bind_reg =~ /^d/  ? "d" :
              $bind_reg =~ /^fp/ ? "f" :
                                   "d";

          push @inputs, "\"$c\"(__v$i)";
      }

      # inline asm body
      print "  __asm volatile (\n";

      # a5 frame pointer swap (always, if used)
      if ($uses_a5) {
          print "                   \"exg %%d7,%%a5\\n\"\n";
      }

      # a4 baserel swap (only in forced_a4 == 2)
      if ($uses_a4 && $forced_a4 == 2) {
          print "                   \"exg %%d6,%%a4\\n\"\n";
      }

      print "                   \"jsr %%a6@(-$bias:W)\\n\"\n";

      if ($uses_a4 && $forced_a4 == 2) {
          print "                   \"exg %%d6,%%a4\\n\"\n";
      }

      if ($uses_a5) {
          print "                   \"exg %%d7,%%a5\\n\"\n";
      }

      # outputs
      if ($is_void) {
          print "                   :\n";
      } else {
          print "                   : \"=r\"(__v_ret)\n";
      }

      # inputs
      print "                   : " . join(", ", @inputs) . "\n";

      # clobbers (no a5/d7 or a4/d6 here)
      my @clobbers = ("d1", "a0", "a1", "fp0", "fp1", "cc", "memory");

      # d0 only clobbered for void functions
      push @clobbers, "d0" if $is_void;

      print "                   : \"" . join("\", \"", @clobbers) . "\" );\n";

      if ($is_void) {
          print "}\n\n";
      } else {
          print "  return __v_ret;\n}\n\n";
      }
      
      # Generate aliases for regular function
      $self->generate_aliases(%params);
    }
}