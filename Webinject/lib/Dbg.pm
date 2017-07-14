package Dbg;

use B;

use base 'Exporter';

our $DEBUG_LEVEL = 0;
our @EXPORT = qw(__dbg);

sub __dbg (&;$) {
    my ($code, $verbosity) = @_;
    if ($DEBUG_LEVEL >= ($verbosity // 1)) {
        my $msg = join('', map { $_ // '' } $code->());
        print STDERR "DEBUG: ", $msg, "\n" if length($msg);
    }
    return;
}

sub trace_subs {
    my ($class, @packages_to_trace) = @_;
    
    foreach my $package (@packages_to_trace) {
        ## no critic
        no strict 'refs';
        ## use critic
        no warnings 'redefine';        
        
        my @subs = grep { 
            defined(&{"${package}::$_"}) &&
            B::svref_2object(\&{"${package}::$_"})->GV->STASH->NAME eq $package
        } keys %{"${package}::"};

        my %patched = ($package eq __PACKAGE__) 
                    ? ('__dbg' => 1, 'trace_subs' => 1)
                    : ();
        
        foreach (@subs) {            
            unless (exists $patched{$_}) {
                $patched{$_} = 1;
                my $p = prototype("${package}::$_");
                $p = defined($p) ? "($p)" : '';            
                __dbg { "Monkeypatching '${package}::$_$p' for tracing..." } 5;
                my $fname = $_;
                my $fn = \&{"${package}::$_"};
                *{"${package}::$_"} = eval qq{sub $p {
                    my \@args = \@_;
                    __dbg { "TRACE: Starting ${package}::${fname}(", join(',', \@args), ')' } 3;
                    if (!defined(wantarray)) {
                        \$fn->(\@args);
                        __dbg { "TRACE: Ending ${package}::${fname}" } 4;
                    }                
                    elsif (wantarray) {
                        my \@ret = \$fn->(\@args);
                        __dbg { "TRACE: Ending ${package}::${fname} with return values: (", join(',', \@ret), ')' } 4;
                        return \@ret;
                    }
                    else {
                        my \$ret = \$fn->(\@args);
                        __dbg { "TRACE: Ending ${package}::${fname} with return value: ", (\$ret // '<UNDEF>') } 4;
                        return \$ret;
                    }
                }}
            }
        }  
    }
    return;
}

1;
__END__
