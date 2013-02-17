#!/usr/bin/perl

use strict;
use Data::Dumper;

# http://search.cpan.org/~lembark/LinkedList-Single-v0.99.21/lib/LinkedList/Single.pm

# This works with our list of lists. Note the function is call dclone().
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

# This works with our lists of lists and may be faster than Storable.
# use Clone qw(clone);

# Using $#table works if we loop by decrementing, even if we are adding rows with push() inside the loop.

require "stll_lib.pl";
require "common_lib.pl";

{
    my $stream = 0;
    
    foreach my $rowc (0..3)
    {
        insert_rec();
        set_eenv('var1', "v1: $rowc");
        set_eenv('var2', "v2: $rowc");
        set_eenv('var3', "v3: $rowc");
        set_eenv('_stream', $stream);
        rewind();
    }
    
    treset();
    while(s_unwind($stream))
    {
        # print Dumper(get_ref_eenv());
        if (get_eenv('var1') eq "v1: 1" || get_eenv('var1') eq "v1: 2" )
        {
            set_eenv('_stream', 1)
        }
        else
        {
            set_eenv('_stream', 2);
        }
        rewind();
    }
    
    # start running code on the streams
    # inner outer if-stmt must run first.
    
    treset();
    while(s_unwind(1))
    {
        print "in loop\n";
        set_eenv('var1', "pie");
          set_eenv('_stream', 3);
          # Changed eenv to the new row!
          clone();
          set_eenv('var1', get_eenv('var1') . " new row from var1");
      }
    
    # inner if-stmt must run second
    # Important: since this is the inner-if it *must* only operate on stream 3!!!

    # Alternately we could leave the "good" stream set to 3, and change the complement (else) to stream 5.
    
    {
        my $lst = 3; # local stream in this block
        treset();
        while(s_unwind($lst))
        {
            print "loopx\n";
            if (get_eenv('var2') eq "v2: 2")
            {
                set_eenv('_stream', 4);
            }
            else
            {
                set_eenv('_stream', 5);
            }
        }
        
        $lst = 4;
        treset();
        while(s_unwind($lst))
        {
            my $var2 = get_eenv('var2');
            $var2 .= " cheesecake";
            set_eenv('var2', $var2);
            set_eenv('_stream', 5);
            clone();
            set_eenv('var1', "new row from var2");
        }
    }
    
    tell_streams();
    # In theory, we could have run this earlier.

    treset();
    while(s_unwind(2))
    {
        my $var1 = get_eenv('var1');
        $var1 .= " cake";
        set_eenv('var1', $var1);
        set_eenv('varx', "new column");
        set_eenv('_stream', 5);
    }

    print dumpt();
    tell_streams();
    exit();

    # # A new line of deft code.
    # # Add a new column. No nesting, no cloning rows.

    # for(my $row=$#table; $row >= 0; $row--)
    # {
    #     my $hr = $table[$row][$depth];
    #     if ($hr->{_stream} == 5)
    #     {
    #         $hr->{var4} = "new col $row";
    #         $hr->{_stream} = 6;
    #     }
    #     # No nesting or subs so no need to inc the stream.
    # }
    
    # printf ("ff: %s\n", Dumper(\@table));
    exit();

}
