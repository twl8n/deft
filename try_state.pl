#!/usr/bin/perl

use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Usage: ./try_deftish.pl

# Use require because deftish.pm is just perl, not a package.
require 'deftish.pm';

# require "cmlib.deft";

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
        newc('_d_state');
    };
    unwind($fref);

    $fref = sub
    { 
        no strict;
        $_d_state = "page_search";
        read_ws_data("states.dat", '_d_order', '_d_edge','_d_test', '_d_func', '_d_next');
    };
    unwind($fref);
    unwind($dump);

    exit();


    my $clear_cont = sub
    {
        no strict;
        $continue = 0;
    };

    # Must name our current state $_d_state
    # deft_cgi();
    # States are read in each time we test one. See read_ws_data() in
    # test_edges().

    call_state();

    # While perhaps not the standard meanings, to avoid confusion,
    # we use these definitions:
    # "state" is a group of edges (e.g. same label) in the state table.
    # "edge" is one entry (line) in the state table)
}

sub call_state
{

    my $fref = sub
    {
        no strict;
        $test_counter = 0;
        $next_state = "";
    };
    unwind($fref);

    test_edges();
    #write_log("next_state1: $next_state");

    $fref = sub
    {
        no strict;
        if ($next_state ne "wait")
        {
            $_prev_state = $_d_state;
            $_d_state = $next_state;
            #write_log("next_state2: $next_state");
            if (! $_d_state)
            {
                write_log("_d_state undefined. prev: $_prev_state");
                exit(1);
            }
            # Fix this. Can't have a perl call in unwind sub.
            call_state();
        }
    };
    unwind($fref);
};



# ./index.pl _d_state="page_search" site_gen="1" site_name="bmw2002"
# In and out streams don't seem to match. Var init/scoping
# or compiler error?


# ordinal label [!]test function new-label
# $true is a special always true test.
# null() is a special no op func.
# $false is only useful for disabling an edge during debugging
# 0/1 should work in place of $true
# !$var should work.
# See states.dat, readme.txt

# duc($marker_flag; # Noah needs to create a comment for this. ()');
# keep_row() where the test var is true?
# desc() and distinct_on().


sub test_edges
{
    
    my $fref = sub
    {
        read_ws_data("states.dat", "_d_order,_d_edge,_d_test,_d_func,_d_next");
    };
    unwind($fref);

    # throw out comments
    # keep_row('($temp  !~ m/^#/)');

    $fref = sub
    {
        no strict;
        if (($_d_order == $test_counter) && ($_d_edge eq $_d_state))
        {
            $_d_test =~ s/\$//;
        
            if ($_d_test eq "true" || get_eenv($_d_test))
            {
                $_d_result = 1;
            } else
            {
                $_d_result = 0;
            }
        }
        $_d_result = 0;
    };
    unwind($fref);

    $fref = sub
    {
        no strict;
        if ( $_d_result ) 
        {
            # When using call_deft(), only want the sub name, not ().
            # Need agg_simple() around call_deft() or inside call_deft().
            # $_d_func =~ s/\(\)//;
        
            if ($_d_func !~ m/null/)
            {
                #write_log("dispatching:$_d_func _d_next:$_d_next");
                dispatch("_d_func");
            }
            $next_state = $_d_next;
            #write_log("ns:$next_state _d_next:$_d_next");
        }
    };
    unwind($fref);

    $fref = sub
    {
        no strict;
        if ((!$_d_result) || ($next_state eq 'next'))
        {
            $test_counter++;
            test_edges();
        }
    };
    unwind($fref);
}


