BEGIN {
    package MacroGCC;
    use vars qw(@ISA);
    @ISA = qw( Macro );   # reuse ctor/header/footer from Macro

    # In the package scope, keep track of the last non-varargs function
    our $LAST_FUNCTION_NAME = '';
    our $LAST_FUNCTION_PARAM_COUNT = 0;
    our $LAST_FUNCTION_LAST_TYPE = '';

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

      print "/* Automatically generated header (sfdc SFDC_VERSION)! Do not edit! */\n";
      print "\n";
      print "#ifndef _INLINE_$$sfd{'BASENAME'}_H\n";
      print "#define _INLINE_$$sfd{'BASENAME'}_H\n\n";
      
      print "#ifndef _PROTO_$$sfd{'BASENAME'}_H\n";
      print "#include <proto/$$sfd{'basename'}.h>\n";
      print "#endif\n\n";
      
      print <<'EOF';
#if defined(__GNUC__)
# if (__GNUC__ >= 8)
#  define AMIGA_VA_WRAPPER_ATTR \
    __attribute__((noipa, noinline, optimize("omit-frame-pointer"), optimize("O1")))
# else
#  define AMIGA_VA_WRAPPER_ATTR \
    __attribute__((noinline, optimize("omit-frame-pointer"), optimize("O1")))
# endif
#else
# define AMIGA_VA_WRAPPER_ATTR
#endif

EOF
      
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

    # Helper: Check if a type uses multiple registers
    sub is_multi_register_type {
        my ($self, $type) = @_;
        # 64-bit integers and doubles use d0:d1 on m68k
        if ($type =~ /LONG LONG|QUAD|int64_t|DOUBLE|double|long long/i) {
            return 1;
        }
        return 0;
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
        
        # Check if the last fixed parameter is a format string
        # (the parameter before the varargs)
        if (@types >= 1) {
            my $last_type = $types[-1];
            if ($last_type =~ /CONST_STRPTR|format/i) {
                return 'format';
            }
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
        
        # Clean parameters - remove "..."
        my ($clean_types, $clean_names) = $self->clean_parameters(\@types, \@names);
        @types = @$clean_types;
        @names = @$clean_names;
        
        my $fixed_count = scalar(@names);
        my $is_void = ($ret =~ /^(VOID|void)$/);
        
        # Get the base function name
        my $taglist_fname = $LAST_FUNCTION_NAME;
        if (!$taglist_fname) {
            $taglist_fname = $fname;
            if ($fname =~ /Tags$/) {
                $taglist_fname =~ s/Tags$/TagList/;
            } else {
                $taglist_fname .= 'A';
            }
        }
        
        # Determine how many fixed parameters to pass to the base function:
        # - If varargs has SAME number of fixed params as base: last fixed param is the first tag (exclude it)
        # - If varargs has FEWER fixed params than base: all fixed params are real params (include all)
        my $pass_count = $fixed_count;
        if ($fixed_count == $LAST_FUNCTION_PARAM_COUNT) {
            $pass_count = $fixed_count - 1;
        }
        
        # Build parameter lists
        my @param_decl = map { "$types[$_] $names[$_]" } (0 .. $fixed_count-1);
        my @param_names = @names;
        my @pass_names = @names[0 .. $pass_count-1];
        
        # The array pointer must have the type of the base function's last
        # parameter (e.g. DoGadgetMethodA takes Msg, not a TagItem list).
        my $cast = $LAST_FUNCTION_LAST_TYPE || 'CONST struct TagItem *';
        
        # Get base macro name
        my $base_macro = $self->{BASE};

        # Emit static helper definition - base is first parameter in a6
        print "AMIGA_VA_WRAPPER_ATTR\n";
        print "static __stdargs $ret __${fname}_va(void *const __base asm(\"a6\")";
        if (@param_decl) {
            print ", ";
        }
        print join(", ", @param_decl);
        print ", ...)\n{\n";
        
        my $last_fixed = $names[$fixed_count-1];
        if ($pass_count == $fixed_count) {
            # All fixed parameters are real parameters of the base function,
            # so the array starts at the first variadic slot, one past the
            # last named one (e.g. EasyRequest's format arguments).
            print "    const ULONG *tags = (const ULONG *)(&$last_fixed + 1);\n";
        } else {
            # The last fixed parameter is the first array element.
            print "    const ULONG *tags = (const ULONG *)&$last_fixed;\n";
        }
        
        # Build the call to the base function
        my @call_args = @pass_names;
        push @call_args, "($cast)tags";
        
        if ($is_void) {
            print "    __${taglist_fname}_base(__base, " . join(", ", @call_args) . ");\n";
        } else {
            print "    return __${taglist_fname}_base(__base, " . join(", ", @call_args) . ");\n";
        }
        print "}\n\n";
        
        # Emit macro wrapper - passes base as argument
        print "#define $fname(...) __${fname}_va($base_macro, __VA_ARGS__)\n\n";
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
        
        # Build parameter lists
        my @param_decl = map { "$types[$_] $names[$_]" } (0 .. $fixed_count-1);
        my @param_names = @names;
        
        # Get base macro name
        my $base_macro = $self->{BASE};

        # Emit helper definition
        print "AMIGA_VA_WRAPPER_ATTR\n";
        print "static __stdargs $ret __${fname}_va(void *const __base asm(\"a6\")";
        if (@param_decl) {
            print ", ";
        }
        print join(", ", @param_decl);
        print ", ...)\n{\n";
        
        # Get the last fixed parameter name
        my $last_fixed = $names[$fixed_count-1];
        
        # With __stdargs, all parameters are on the stack: the slot after the
        # last fixed parameter is the start of the varargs.
        print "    const void *args = (const void *)(&$last_fixed + 1);\n";
        
        my @call_args = @param_names;
        push @call_args, "args";

        if ($is_void) {
            print "    __${v_fname}_base(__base, " . join(", ", @call_args) . ");\n";
        } else {
            print "    return __${v_fname}_base(__base, " . join(", ", @call_args) . ");\n";
        }
        print "}\n\n";
        
        # Emit macro wrapper - passes base as first parameter
        print "#define $fname(";
        print join(", ", @param_names);
        if (@param_names) {
            print ", ";
        }
        print "...) __${fname}_va($base_macro";
        if (@param_names) {
            print ", ";
        }
        print join(", ", @param_names);
        if (@param_names) {
            print ", ";
        }
        print "## __VA_ARGS__)\n\n";
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
        
        # Build parameter lists
        my @param_decl = map { "$types[$_] $names[$_]" } (0 .. $fixed_count-1);
        my @param_names = @names;
        
        # Get base macro name
        my $base_macro = $self->{BASE};
     
        # Emit helper definition - base is first parameter in a6
        print "AMIGA_VA_WRAPPER_ATTR\n";
        print "static __stdargs $ret __${fname}_va(void *const __base asm(\"a6\")";
        if (@param_decl) {
            print ", ";
        }
        print join(", ", @param_decl);
        print ", ...)\n{\n";
        
        print "    LONG args[5] = {0, 0, 0, 0, 0};\n";
        print "    int count = 0;\n";
        
        # Get the last fixed parameter
        my $last_fixed = $names[$fixed_count-1];
        print "    const LONG *argptr = (const LONG *)&$last_fixed + 1;\n";
        print "    \n";
        print "    while (count < 5 && argptr) {\n";
        print "        args[count++] = *argptr++;\n";
        print "    }\n";
        print "    \n";
        
        my @call_args = @param_names;
        push @call_args, "args[0], args[1], args[2], args[3], args[4]";
        
        if ($is_void) {
            print "    DoPkt(" . join(", ", @call_args) . ");\n";
        } else {
            print "    return DoPkt(" . join(", ", @call_args) . ");\n";
        }
        print "}\n\n";
        
        # Emit macro wrapper
        print "#define $fname(";
        print join(", ", @param_names);
        if (@param_names) {
            print ", ";
        }
        print "...) __${fname}_va($base_macro";
        if (@param_names) {
            print ", ";
        }
        print join(", ", @param_names);
        if (@param_names) {
            print ", ";
        }
        print "## __VA_ARGS__)\n\n";
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
            my @alias_decl = map { rewrite_type_for_declaration($alias_types[$_], $alias_names[$_]) } (0 .. $#alias_types);
            print join(", ", @alias_decl);
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
              $self->generate_taglist_varargs(%params);
          }
          
          $self->generate_aliases(%params);
          return;
      }

      # Store this function name and param count for potential varargs that follow
      $LAST_FUNCTION_NAME = $fname;
      $LAST_FUNCTION_PARAM_COUNT = scalar(@types);
      $LAST_FUNCTION_LAST_TYPE = @types ? $types[-1] : '';

      my $forced_a4 = $params{'forced_a4'} // 0;

      my $uses_a5 = 0;
      my $uses_a4 = 0;
      for my $r (@regs) {
          next unless defined $r && $r ne '';
          $uses_a5 = 1 if $r eq 'a5';
          $uses_a4 = 1 if $r eq 'a4';
      }

      if ($uses_a4 && $forced_a4 == 0) {
          print "#ifndef __baserel__\n";
          $self->function(%params, forced_a4 => 1);
          print "#else\n";
          $self->function(%params, forced_a4 => 2);
          print "#endif /* __baserel__ */\n\n";
          return;
      }

      my $base_macro = $self->{BASE};

      # Generate the base inline assembly macro (__${fname}_base)
      print "#define __${fname}_base(__in_base";
      if (@names) {
		print ", ";
	  }
      print join(", ", @names);
      print ") ({\\\n";

      # Evaluate all parameters into local variables FIRST
      # This prevents function call parameters from being clobbered
      # by register assignments for inline assembly.
      for my $i (0 .. $#types) {
          my $clean_type = $types[$i];
          $clean_type =~ s/^\s*(const|CONST)\s+//;
          $clean_type =~ s/^CONST_//;
          
          # For function pointer types, use void * to avoid declaration syntax issues
          if ($clean_type =~ /\(\s*\*\s*\)\s*\(/) {
              print "  void *__p_$names[$i] = (void *)($names[$i]);\\\n";
          } else {
              print "  $clean_type __p_$names[$i] = ($clean_type)($names[$i]);\\\n";
          }
      }

      # Return register (always create for non-void)
      if (!$is_void) {
          print "  register $ret __v_ret __asm(\"d0\");\\\n";
      }

      my %used_regs = ();
      
      # Check if any parameter uses a multi-register type
      my $uses_d1_for_param = 0;
      my $uses_a1_for_param = 0;
      
      my $uses_d1_for_return = 0;
      if ($self->is_multi_register_type($ret)) {
		$uses_d1_for_return = 1;
	  }
      
      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';
          
          my $bind_reg =
              ($r eq 'a5')               ? 'd7' :
              ($r eq 'a4' && $forced_a4 == 2) ? 'd6' :
                                                $r;
          
          # Check if this register uses a multi-register type
          if (($bind_reg eq 'd0' || $bind_reg eq 'd1') && 
              $self->is_multi_register_type($types[$i])) {
              $uses_d1_for_param = 1;
          }
          
          if (($bind_reg eq 'a0' || $bind_reg eq 'a1') && 
              $self->is_multi_register_type($types[$i])) {
              $uses_a1_for_param = 1;
          }
      }

      # Check if d0 is used with a multi-register type AND we have a return value
      my $d0_is_multi = 0;
      my $d1_used_as_param = 0;
      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';
          if ($r eq 'd0' && $self->is_multi_register_type($types[$i])) {
              $d0_is_multi = 1;
          }
          if ($r eq 'd1') {
              $d1_used_as_param = 1;
          }
      }

      # bind args to their registers using the evaluated local variables
      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';

          my $bind_reg =
              ($r eq 'a5')               ? 'd7' :
              ($r eq 'a4' && $forced_a4 == 2) ? 'd6' :
                                                $r;

          # Clean the type for register declaration
          my $clean_type = $types[$i];
          $clean_type =~ s/^\s*(const|CONST)\s+//;
          $clean_type =~ s/^CONST_//;

          my $decl = rewrite_type_for_declaration($clean_type, "__v$i");
          
          print "  register $decl __asm(\"$bind_reg\") = __p_$names[$i];\\\n";
          
          $used_regs{$bind_reg} = 1;
      }

      my @clobbers = ("fp0", "fp1", "cc", "memory");
      
      # d0 is only clobbered if void (no return value)
      if ($is_void && !$used_regs{'d0'}) {
          push @clobbers, "d0";
      }
      
      # d1 is clobbered if not used as a parameter AND not used by a multi-register type
      if (!$used_regs{'d1'} && !$uses_d1_for_param && !$uses_d1_for_return) {
          push @clobbers, "d1";
      }
      
      # a0 is clobbered if not used as a parameter
      if (!$used_regs{'a0'}) {
          push @clobbers, "a0";
      }
      
      # a1 is clobbered if not used as a parameter AND not used by a multi-register type
      if (!$used_regs{'a1'} && !$uses_a1_for_param) {
          push @clobbers, "a1";
      }

      my @inputs;
      my @outputs;

      # The base must be an input of the same asm statement as the jsr:
      # __v_base's liveness alone does not reach it, and without the
      # operand gcc is free to reuse a6 as scratch between the outer
      # macro and the call.
      push @inputs, "\"a\"(__in_base)";

      # Return register
      if (!$is_void) {
          push @outputs, "\"=d\"(__v_ret)";
      }
      
      # For each parameter
      for my $i (0 .. $#types) {
          my $r = $regs[$i];
          next unless defined $r && $r ne '';

          my $bind_reg =
              ($r eq 'a5')               ? 'd7' :
              ($r eq 'a4' && $forced_a4 == 2) ? 'd6' :
                                                $r;

          my $c =
              $bind_reg =~ /^a/  ? "a" :
              $bind_reg =~ /^d/  ? "d" :
              $bind_reg =~ /^fp/ ? "f" :
                                   "d";

          # Check if this is a clobberable register (d0, d1, a0, a1)
          my $is_clobberable = ($bind_reg =~ /^(d0|d1|a0|a1)$/);
          
          if ($is_clobberable) {
              # If it's d0 and we have a return value, it's an input
              # (the return value is a separate output)
              if ($bind_reg eq 'd0' && !$is_void) {
                  # d0 is a parameter, but return is also in d0
                  # Use input only for the parameter
                  push @inputs, "\"$c\"(__v$i)";
              } else {
                  # Other clobberable registers are in/out
                  push @outputs, "\"+$c\"(__v$i)";
              }
          } else {
              # Other registers are preserved by the callee, so just input
              push @inputs, "\"$c\"(__v$i)";
          }
      }
      
      # If d0 is multi-register (DOUBLE) and we have a return value,
      # add dummy d1 output if d1 isn't already used as a parameter
      if ($d0_is_multi && !$is_void && !$d1_used_as_param) {
          print "  register LONG __v_d1 __asm(\"d1\");\\\n";
          push @outputs, "\"=d\"(__v_d1)";
      }

      print "  __asm volatile (\\\n";

      if ($uses_a5) {
          print "                   \"exg %%d7,%%a5\\n\"\\\n";
      }

      if ($uses_a4 && $forced_a4 == 2) {
          print "                   \"exg %%d6,%%a4\\n\"\\\n";
      }

      print "                   \"jsr %%a6@(-$bias:W)\\n\"\\\n";

      if ($uses_a4 && $forced_a4 == 2) {
          print "                   \"exg %%d6,%%a4\\n\"\\\n";
      }

      if ($uses_a5) {
          print "                   \"exg %%d7,%%a5\\n\"\\\n";
      }

      # outputs
      my @all_outputs = @outputs;
      
      if (@all_outputs) {
          print "                   : " . join(", ", @all_outputs) . "\\\n";
      } else {
          print "                   :\\\n";
      }

      # inputs
      print "                   : " . join(", ", @inputs) . "\\\n";

      # clobbers
      if (@clobbers) {
          print "                   : \"" . join("\", \"", @clobbers) . "\" );\\\n";
      } else {
          print "                   : );\\\n";
      }

      if ($is_void) {
          print "})\n\n";
      } else {
          print "  __v_ret;})\n\n";
      }

      # Generate the public macro that sets up a6
      print "#define $fname(";
      print join(", ", @names);
      print ") ({\\\n";
      print "  register void *const __v_base __asm(\"a6\") = $base_macro;\\\n";
      print "  __${fname}_base(__v_base";
      if (@names) {
        print ", ";
      }
      print join(", ", @names);
      print ");\\\n";
      print "})\n\n";
      
      $self->generate_aliases(%params);
    }
}