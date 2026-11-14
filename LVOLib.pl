
### Class LVOLib: Create the LVO symbols of a link library #####################

# The same offsets as the LVO include file, as global absolute symbols in an
# assembler source of its own: assembled into a link library, they resolve
# the _LVO references of programs that do not include the LVO files.

BEGIN {
    package LVOLib;
    use strict;
    use warnings;

    sub new {
      my $proto  = shift;
      my %params = @_;
      my $class  = ref($proto) || $proto;
      my $self   = {};
      $self->{SFD} = $params{'sfd'};
      bless ($self, $class);
      return $self;
    }

    sub header {
      my $self = shift;
      my $sfd  = $self->{SFD};

      print "/* Automatically generated LVO symbols (sfdc SFDC_VERSION)! Do not edit! */\n";
      print "\n";
    }

    sub function {
      my $self      = shift;
      my %params    = @_;
      my $prototype = $params{'prototype'};

      # Private functions too: amiga.lib has always named their vectors

      if ($prototype->{type} eq 'function') {
          print "\t.globl\t_LVO$prototype->{funcname}\n";
          print "_LVO$prototype->{funcname} = -$prototype->{bias}\n";
      }
    }

    sub footer {
      # Nothing to do here ...
    }
}
