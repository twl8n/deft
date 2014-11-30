#!/usr/bin/perl

use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Usage: ./try_deftish.pl

# Use require because deftish.pm is just perl, not a package.
require 'deftish.pm';

main();

sub main
{
    # init();

    my $dump = sub
    {
        no strict;
        print Dumper(hr());
    };

    my $fref = sub
    { 
        no strict;
        read_ws_data("states.dat", '_d_order', '_d_edge','_d_test', '_d_func', '_d_next');
    };
    unwind($fref);
    unwind($dump);
}
