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
    my $in_stream = 0;

    foreach my $rowc (0..3)
    {
        insert_rec();
        set_eenv('var1', "v1: $rowc");
        set_eenv('var2', "v2: $rowc");
        set_eenv('var3', "v3: $rowc");
        set_eenv('_stream', $in_stream);
        rewind();
    }

    treset();
    while(unwind())
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

    treset();
    while(s_unwind(3))
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

    treset();
    while(s_unwind(4))
    {
        my $var2 = get_eenv('var2');
        $var2 .= " cheesecake";
        set_eenv('var2', $var2);
        set_eenv('_stream', 5);
        clone();
        set_eenv('var1', "new row from var2");
    }


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
    
    if (0)
    {
        my @list = (0..3);
        my $xx = 0;
        my $max = $#list;
        foreach my $val (0..$max)
        {
            print "val: $list[$val]\n";
            push(@list, "new $val");
            $xx++;
            if ($xx > 20)
            {
                exit();
            }
        }
    
        $xx = 0;
        $max = $#list/2;
        foreach my $val (0..$max)
        {
        
        }

        print Dumper(\@list);
        exit();
    }

    exit();


    if (0)
    {
        my $in_stream = 0;
        my $out_stream = $in_stream+1;
        
        my @table;
        $table[$in_stream] = undef;
        foreach my $rowc (0..3)
        {
            # $table[$rowc][0] = {var1 => "v1: $rowc", var2=> "v2: $rowc", var3 => "v3: $rowc"};

            my $prev = undef;
            my $next = undef;
            my %hrow = (var1 => "v1: $rowc", var2=> "v2: $rowc", var3 => "v3: $rowc", _prev => '', _next => '');

            if ($table[$in_stream])
            {
                $prev = \%{$table[$in_stream]};
                printf "Have a prev: %s\n", $prev ;
                $hrow{_next} = $prev;
                $prev->{_prev} = \%hrow;
            }

            $table[$in_stream] = \%hrow;
        }

        printf "first: %s\n", Dumper(\@table);

        $Data::Dumper::Maxdepth = 1;
        my $hr = $table[$in_stream];
        printf "ll: %s\n", Dumper($hr);
        while ( $hr->{_next})
        {
            $hr = $hr->{_next};
            printf "ll: %s\n", Dumper($hr);
        }

        $hr = $table[$in_stream];

        while ( $hr->{_next})
        {
            my $row = 0;
            # Use hash slice as both lvalue and value.
            @{$table[$row][1]}{qw/xxx1 xxx2/} = @{$table[$row][0]}{qw/var1 var2/};
        }

        foreach my $row (0.. $#table)
        {
            printf "second $row: %s\n", Dumper(\%{$table[$row][1]});
        }

        my $row_max = $#table;
        foreach my $row (0..$row_max)
        {
            $table[$row][1]{xxx2} = "modified $row";
            my $new = dclone(\@{$table[$row]});
            print "new: $new \@{$table[$row]}\n";
            $new->[1]{xxx2} = "really new $row";
            push(@table, $new);
        }
    
        foreach my $row (0.. $#table)
        {
            printf "third $row: %s\n", Dumper(\%{$table[$row][1]});
        }

        printf "third-dumper: %s\n", Dumper(\@table);

        #unwind/rewind

        foreach my $row (0..$#table)
        {
            # Use hash slice as both lvalue and value.
            @{$table[$row][0]}{qw/var1 var2/} = @{$table[$row][1]}{qw/xxx1 xxx2/};
            pop(@{$table[$row]});
        }
        printf "post-rewind: %s\n", Dumper(\@table);

    }
}
exit();

my @list = (0..3);

# foreach my $index (0..$#list)
my $max = $#list;
for(my $index = 0; $index <= $max; $index++)
{
    if ($index == 0)
    {
        push(@list, "stuff");
        print "pushed, last: $#list\n";
    }
    print "list: $list[$index]\n";
}

print Dumper(\@list);

exit();

exit;
{
    my $var = "i,like,pie";
    my %vh;
    foreach my $item (split(',', $var))
    {
	$vh{$item} = 1;
    }
    
    print Dumper(\%vh);

}


sub mainx
{
    my $unwind = init_unwind();

    &$unwind("one");
    &$unwind("two");
    &$unwind("three");

}

sub xinit_unwind
{

    my $flag_1 = 1;
    
    return sub 
    {
	if ($flag_1)
	{
	    print "First iter m:$_[0] f:$flag_1\n";
	    $flag_1 = 0;
	    return;
	}
	print "Normal iter m:$_[0] f:$flag_1\n";
    };
}

sub main2
{
    my @row_list = (0,1,2,3,4,5);
    my @th = ("mazda","japan",
	      "mercedes","germany",
	      "ford","america");
	      
    {
	my %rh;
	my $count = 0;
	while (defined(my $var = $row_list[$count]))
	{
	    $count++;
	    $rh{$var} = $th[$var];
	    
	    print "Got $var\n";
	    foreach my $key (keys(%rh))
	    {
		print "$key:$rh{$key}\n";
	    }
	}
    }
    {
	my %rh;
	my $count = 0;
	while (defined(my $var = $row_list[$count]))
	{
	    $count++;
	    $rh{$var} = $th[$var];
	    
	    print "Got $var\n";
	    foreach my $key (keys(%rh))
	    {
		print "$key:$rh{$key}\n";
	    }
	}
    }
}

sub  main1
{
    my $temp = "abc
123";

    if ($temp !~ m/\n$/)
    {
	$temp .= "\n";
    }

    my $xx = 0;
    while($temp)
    {
	$temp =~ s/(.*?)\s+//;
	print "$1\n";
	$xx++;
	if ($xx > 10)
	{
	    print "uh oh $xx\n";
	    exit("");
	}
    }
    print "ok\n";
}


if (0)
{
    my $in_stream = 0;

    foreach my $rowc (0..3)
    {
        #$table[$rowc][0] = {var1 => "v1: $rowc", var2=> "v2: $rowc", var3 => "v3: $rowc", _stream => $in_stream};
        print "$rowc\n";
    }

    my $rowc = 0;
    treset();
    while (my $hr = unwind())
    {
        print "inside while\n";
        my $hr = clone();
        $hr->{var1} = "new row from var1 $rowc";
        $rowc++;
    }

    # print Dumper(\@table);
    exit();
}
