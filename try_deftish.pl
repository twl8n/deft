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

    my $dump = sub
    {
        no strict;
        print Dumper(hr());
    };

    my $fref = sub
    { 
        no strict;
        read_tab_data("./demo.dat", 'sequence', 'make', 'model', 'displacement','units');
    };
    unwind($fref);

    dcc("distinct_units", 
        "units",
        [""],
        [","]);

    dcc("distinct_units", 
        "units",
        [""],
        ["units,at"]);

    unwind($dump);

    # $fref = sub
    # {
    #     my @temp = split(',', "units,displacement");
    #     my $slice_ref = slice_eenv(\@temp);
    #     print Dumper($slice_ref);
    # };
    # unwind($fref);

    exit();

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

    unwind($dump);

    # We can cheat with non-table globals outside the fref. In this case we implement distinct() or agg_simple().
    my %unique;
    $fref = sub
    {
        no strict;
        if (!exists($unique{$units}))
        {
            $unique{$units} = 1;
            print "$units\n";
        }
    };
    unwind($fref);


    # A trial subroutine. The arg is a column name to do something with.  Args are passed to unwind, which
    # strips off the $fref and passes the remaining param list to $fref.
    my $print = sub
    {
        no strict;
        my $arg = $_[0];
        print "$arg: $$arg\n";
    };
    unwind($print, 'units');

    # round to 2 decimal places
    my $round = sub
    {
        no strict;
        my $arg = $_[0];
        $$arg = sprintf("%2.2f", $$arg);
    };
    unwind($round, 'displacement');
    unwind($print, 'displacement');
    unwind($dump);

    
    exit();

} # end main

