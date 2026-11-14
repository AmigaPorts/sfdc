
### Class Stub68k: Create a 68k stub file #####################################

# A stub is a C function that takes its arguments from the stack and makes
# the library call through MacroGCC's inline macro, so that one place knows
# which registers a call binds and clobbers. A varargs stub makes the call of
# the function it belongs to, with the address of its variable arguments.

BEGIN {
    package Stub68k;
    use vars qw(@ISA);
    @ISA = qw( Stub );

    sub new {
      my $proto  = shift;
      my $class  = ref($proto) || $proto;
      my $self   = $class->SUPER::new( @_ );
      $self->{MACRO} = MacroGCC->new( @_ );
      bless ($self, $class);
      return $self;
    }

    # The function whose library vector the stub calls

    sub called {
      my $self      = shift;
      my $prototype = shift;

      return $prototype->{type} eq 'varargs' ?
          $prototype->{real_prototype} : $prototype;
    }

    # A function that takes its base as an argument, in a6 (cia.resource),
    # has a macro without a base parameter

    sub has_base {
      my $self      = shift;
      my $prototype = shift;

      return !grep { $_ eq 'a6' } @{$self->called ($prototype)->{regs}};
    }

    sub function_proto {
      my $self         = shift;
      my %params       = @_;
      my $prototype    = $params{'prototype'};
      my $decl_regular = $params{'decl_regular'};

      if ($prototype->{type} eq 'function' &&
          $prototype->{numargs} > 0 &&
          $prototype->{argnames}[-1] eq '...') {
          print STDERR "$prototype->{funcname}: " .
            "a variable argument list needs ==varargs.\n";
          die;
      }

      if ($prototype->{type} eq 'function' ||
          ($prototype->{type} eq 'varargs' && $decl_regular)) {
          $self->{MACRO}->function (prototype => $self->called ($prototype),
                                    base_only => 1);
      }

      $self->SUPER::function_proto (prototype    => $prototype,
                                    decl_regular => 0);
    }

    sub function_start {
      my $self      = shift;
      my %params    = @_;
      my $prototype = $params{'prototype'};

      if ($prototype->{type} eq 'function' ||
          $prototype->{type} eq 'varargs') {
          my $called = $self->called ($prototype);

          print "\n";
          print "{\n";

          if ($self->has_base ($prototype)) {
            print "  BASE_EXT_DECL\n";
          }

          print "  " . ($called->{nr} ? "" : "return ") .
            "__$called->{funcname}_base(";

          if ($self->has_base ($prototype)) {
            print "BASE_NAME";
          }
      }
      else {
          $self->SUPER::function_start (@_);
      }
    }

    sub function_arg {
      my $self      = shift;
      my %params    = @_;
      my $prototype = $params{'prototype'};
      my $argname   = $params{'argname'};
      my $argnum    = $params{'argnum'};

      if ($prototype->{type} eq 'function' ||
          $prototype->{type} eq 'varargs') {
          my $argstr = $prototype->{type} eq 'varargs' ?
            $self->varargs_arg (@_) : $argname;

          if ($argstr ne '') {
            if ($argnum != 0 || $self->has_base ($prototype)) {
                print ", ";
            }
            print $argstr;
          }
      }
      else {
          $self->SUPER::function_arg (@_);
      }
    }
}
