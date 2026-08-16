
### Class Proto: Create a proto file ##########################################

BEGIN {
    package Proto;

    sub new {
      my $proto    = shift;
      my %params   = @_;
      my $class    = ref($proto) || $proto;
      my $self     = {};
      $self->{SFD} = $params{'sfd'};
      bless ($self, $class);
      return $self;
    }

    sub header {
      my $self = shift;
      my $sfd  = $self->{SFD};

      my $base      = $$sfd{'base'};
      my $basename  = $$sfd{'basename'};
      my $BASENAME  = $$sfd{'BASENAME'};
      my $BaseName  = $$sfd{'BaseName'};
      my $basetype  = $$sfd{'basetype'};

      print "/* Automatically generated header (sfdc SFDC_VERSION)! Do not edit! */\n";
      print "\n";
      print "#ifndef PROTO_${BASENAME}_H\n";
      print "#define PROTO_${BASENAME}_H\n";
      print "\n";
      print "#include <clib/${basename}_protos.h>\n";
      print "\n";

      if ($base ne '') {
          print "#if defined(_CONST_BASES)\n";
		  print "# ifndef __CONSTLIBBASEDECL__\n";
          print "# define __CONSTLIBBASEDECL__ const\n";
          print "# endif /* __CONSTLIBBASEDECL__ */\n";
		  print "# ifndef __SEGMENTLIBBASEDECL__\n";
          print "# define __SEGMENTLIBBASEDECL__  __attribute__((__section__(\".data\")))\n";
          print "# endif /* __SEGMENTLIBBASEDECL__ */\n";
          print "#endif /* _CONST_BASES */\n";

          print "#ifdef __amigaos4__\n";
          print "# include <interfaces/${basename}.h>\n";
          print "# ifndef __NOGLOBALIFACE__\n";
          print "   extern struct ${BaseName}IFace *I${BaseName};\n";
          print "# endif /* __NOGLOBALIFACE__*/\n";
          print "#endif /* !__amigaos4__ */\n";
          print "#ifndef __NOLIBBASE__\n";
          print "  extern ${basetype}\n";
          print "# ifdef __CONSTLIBBASEDECL__\n";
          print "   __CONSTLIBBASEDECL__\n";
          print "# endif /* __CONSTLIBBASEDECL__ */\n";
          print "  ${base}\n";
		  print "# ifdef __SEGMENTLIBBASEDECL__\n";
          print " __SEGMENTLIBBASEDECL__\n";
          print "# endif /* __SEGMENTLIBBASEDECL__ */\n";          
          print ";\n";
          print "#endif /* !__NOLIBBASE__ */\n";
          print "\n";
      }

      print "#ifndef _NO_INLINE\n";
      print "# if defined(__GNUC__)\n";
      print "#  ifdef __AROS__\n";
      print "#   include <defines/${basename}.h>\n";
      print "#  else\n";
      print "#   include <inline/${basename}.h>\n";
      print "#  endif\n";
      print "# else\n";
      print "#  include <pragmas/${basename}_pragmas.h>\n";
      print "# endif\n";
      print "#endif /* _NO_INLINE */\n";
      print "\n";
    }

    sub function {
      # Nothing to do here ...
    }

    sub footer {
      my $self = shift;
      my $sfd  = $self->{SFD};

      print "#endif /* !PROTO_$$sfd{'BASENAME'}_H */\n";
    }
}
