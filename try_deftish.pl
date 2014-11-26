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
    init();

    my $fref = sub
    { 
        no strict;
        read_tab_data("./demo.dat", 'sequence', 'make', 'model', 'displacement','units');
    };
    unwind($fref);

    $fref = sub
    {
        no strict;
        # Even though $$vars work, $hr is not a global. It must be a file global and oddly not visible, even
        # though the $$vars are fine.
        print Dumper(hr());
    };
    unwind($fref);


    $fref = sub 
    {
        no strict;
        newc('liters');
        if ($units eq "cid")
        {
            $liters = (16.39 * $displacement) / 1000;
        }
        elsif ($units eq "cc")
        {
            $liters = ($displacement / 1000);
        }
        elsif ($units eq "cup")
        {
            $liters = ($displacement * 0.236588237);
        }
        elsif ($units eq 'liter')
        {
            $liters = $displacement;
        }
    };
    unwind($fref);

    $fref = sub
    {
        no strict;
        $model = ucfirst($model);
        $make =~ s/^([a-z]{1})/uc($1)/e;
        $make =~ s/(\W{1}[a-z]{1})/uc($1)/e;
    };
    unwind($fref);

    $fref = sub
    {
        no strict;
        print Dumper(hr());
    };
    unwind($fref);


    exit();

} # end main

