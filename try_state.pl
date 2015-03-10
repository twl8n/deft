#!/usr/bin/perl

use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Usage: ./try_deftish.pl

# Use require because deftish.pm is just perl, not a package.
require 'deftish.pm';

# require "cmlib.deft";

our ($_d_state, $next_state, $_d_result, $test_counter);
our (%known, $_prev_state, $_d_order, $_d_edge, $_d_test, $_d_func, $_d_next);
our ($next, $edit, $delete, $insert, $item, $site_gen, $confirm, $save, $continue, $page_gen, $auto_gen, $con_pk, $true);

main();

sub main
{
    $| = 1;

    # init();


    my $dump = sub
    {
        no strict;
        print Dumper(hr());
    };

    # Create a few cols we need.
    unwind(sub { 
               newc('_d_state', 'next_state', '_d_result', 'test_counter');
           });

    my $clear_cont = sub {
        no strict;
        $continue = 0;
    };

    # This was in test_edges() but loading it every time test_edges() recurses was crossmultiplying. I think
    # the original Deft code was doing this in a new scope of the table, and thus this data was lost when that scope closed.

    # _d_order _d_edge        _d_test   _d_func         _d_next
    # 0       page_search     $edit     null()          edit_page
    # 1       page_search     $delete   null()          ask_delete_page

    unwind(sub
           {
               read_ws_data("states.dat", '_d_order', '_d_edge', '_d_test', '_d_func', '_d_next');
           });
    
    # Auto create a col for each unique test. $true is true, the rest default to false.
    unwind(sub
           {
               $_d_test =~ s/^\$//;
               if (! exists($known{$_d_test}))
               {
                   $known{$_d_test} = 1;
                   newc($_d_test);
               }
               # if ($_d_test eq 'true')
               # {
               #     set_eenv($_d_test, 1);
               # }
               # else
               # {
               #     set_eenv($_d_test, 0);
               # }
           });

    # Set defaults
    unwind(sub
           { 
               no strict;
               $_d_state = "page_search";
               reset_tests();
               # $edit = 1;
               # $_d_state = "edit_page";
               # $save = 1;
           });

    my $fref = sub
    {
        if ($_d_edge eq $true)
        {
            print "";
        }
    };
    # unwind($fref);

    while(1)
    {
        call_state();
        # unwind(sub {
        #            if (! $next)
        #            {
        #                reset_tests();
        #            }});
        unwind(sub {
                   if ($_d_edge eq $_d_state)
                   {
                       print "Action:  $_d_order $_d_test\n";
                   }
               });
        print "\nChoose one:";
        my $var = <>;

        # (Wrong) Instead of $$_d_test (dollar dollar sigil) must use set_eenv() and $_d_test.  Whatever test
        # is in $_d_test needs to be set to true. If $_d_test == 'edit' then $edit=1 or set_eenv('edit', 1);
        
        # Ok. This didn't work and is actually not necessary. When is set_eenv() necessary?  When could is
        # possibly work? The last thing that happens at the end of unwind() is copying the $var over the
        # $hr->{$var} in the table. Therefore set_eenv() can never work, unless there was a column that did
        # not previously exist.
        
        # set_eenv($_d_test, 1);
        unwind(sub {
                   if ($_d_order == $var && $_d_edge eq $_d_state)
                   {
                       no strict;
                       # $$_d_test works. 
                       $$_d_test = 1;
                       print "selected: next: $next edit: $edit\n";
                   }
               });
    }    

    # While perhaps not the standard meanings, to avoid confusion,
    # we use these definitions:
    # "state" is a group of edges (e.g. same label) in the state table.
    # "edge" is one entry (line) in the state table)
}

sub call_state
{
    my $return_flag = 0;
    unwind(sub
           {
               $test_counter = 0;
               $next_state = "";
           });

    test_edges();
    # print("test_edges() done, next_state1: $next_state\n");

    # unwind(sub { print "test_edges() done next: $next _d_order: $_d_order\n"; });

    unwind(sub
           {
               if ($next_state ne "wait")
               {
                   $_prev_state = $_d_state;
                   $_d_state = $next_state;
                   if (! $_d_state)
                   {
                       print("_d_state undefined. prev: $_prev_state\n");
                       print Dumper(hr());
                       exit(1);
                   }
                   # if ($next_state ne 'next')
                   if ( ! $next)
                   {
                       $return_flag = 1;
                   }
               }
               elsif ($next_state eq 'wait')
               {
                   $return_flag = 1;
               }
           });

    if ($return_flag)
    {
        print "call_state() returning\n";
        return;
    }
    # Fix this. Can't have a perl call in unwind sub. Or can we? 
    call_state();
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
    my $return_flag = 0;
    my $return_state = '';
    # throw out comments
    # keep_row('($temp  !~ m/^#/)');

    # Need to either throw out everything we don't want, or somehow restrict all the unwind calls below to
    # just a few rows. The recursion test at the end depends on only a small number of rows. 

    # keep_row('($_d_order == $test_counter) && ($_d_edge eq $_d_state)');

    keep(sub 
         {
             return (($_d_order == $test_counter) && ($_d_edge eq $_d_state));
         });
    
    unwind(sub { print Dumper(hr()); });

    exit();

    unwind(sub
           {
               # print Dumper(hr());
               # print "tc: $test_counter do: $_d_order ds: $_d_state de: $_d_edge\n";
               if (($_d_order == $test_counter) && ($_d_edge eq $_d_state))
               {
                   print "M-3: _d_test: $_d_test edit: $edit eenv($_d_test): " . get_eenv($_d_test) . " tc: $test_counter do: $_d_order ds: $_d_state de: $_d_edge\n";

                   $_d_test =~ s/^\$//;
                   if ($_d_test eq "true" || get_eenv($_d_test))
                   {
                       # print "_d_test: $_d_test tc: $test_counter do: $_d_order ds: $_d_state de: $_d_edge\n";
                       print "M-1: _d_test: $_d_test get_eenv($_d_test): " . get_eenv($_d_test) . "\n";
                       print "M-1: tc: $test_counter do: $_d_order ds: $_d_state de: $_d_edge\n";
                       $_d_result = 1;
                   }
                   else
                   {
                       $_d_result = 0;
                   }
               }
               else
               {
                   $_d_result = 0;
               }
           });

    my $dump = sub
    {
        print "rowc: " . rowc() . "\n";
        print "hr: " . Dumper(hr());
    };

    unwind(sub
           {
               if ( $_d_result ) 
               {
                   # When using call_deft(), only want the sub name, not ().
                   # Need agg_simple() around call_deft() or inside call_deft().
                   # $_d_func =~ s/\(\)//;
        
                   if ($_d_func !~ m/null/)
                   {
                       # Press return...
                       #print("dispatching:$_d_func _d_next:$_d_next");
                       dispatch("_d_func");
                   }
                   $next_state = $_d_next;
                   if ($_d_next eq 'next')
                   {
                       $next_state = $_d_state; # When next, state stays the same.
                       reset_tests();
                       $next = 1; # When next, set $next to true.
                   }
                   # $return_state = $_d_next;
                   $return_state = $next_state;
                   print("ns:$next_state _d_next:$_d_next _d_state:$_d_state _d_order: $_d_order\n");
                   $return_flag = 1;
                   # It seems wrong and unsafe to return from inside an unwind, and returning here didn't work. I
                   # guess it was returning only from unwind and not from test_edges.
               }
           });

    if ($return_flag)
    {
        unwind(sub
               {
                   $next_state = $return_state;
                   $test_counter = 0;
                   # print "have rf: next: $next _d_order: $_d_order return_state: $return_state\n";
               });
        return;
    }


    unwind(sub
           {
               # if (($_d_order == $test_counter) && ($_d_edge eq $_d_state))

               # I think we want to increment test_counter for all the states with matching edges. If our state is
               # 'page_search' then we want all the edges with 'page_search' to test $_d_order against the
               # incremented test_counter, and that means they all need to be incremented.

               if ($_d_edge eq $_d_state)
               {
                   # if ((!$_d_result) || ($next_state eq 'next'))
                   if ((!$_d_result) || ($next == 1))
                   {
                       $test_counter++;
                       # Normally, this is where we would use $$test_counter (note the 2 '$' chars).

                       # Must set_eenv() or invent a rewind because the $$var won't be written back
                       # to the table until after $fref has completed each iteration.

                       set_eenv('test_counter', $test_counter);
                       # print "M-2: tc: $test_counter\n";
                   }
               }
           });

    # unwind($dump);

    # In deft5 where this works, test_edges() is inside the if() statement, but only "inside" in the sense of
    # stream management. The call to test_edges() is *not* inside the same unwind block as $test_counter++.
    
    test_edges();
}

# Must be called inside unwind().
sub reset_tests()
{
    # Reset all tests to false, except $true which is always true.
    no strict;
    # print "setting $_d_test to 0\n";
    $$_d_test = 0;
    if ($_d_test eq 'true')
    {
        $true = 1;
        print "setting true to 1\n";
        # set_eenv($_d_test, 1);
    }
    # {
    #     set_eenv($_d_test, 0);
    # }
}
