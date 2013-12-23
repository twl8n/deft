#!/usr/bin/perl

use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Usage: ./try.pl

# Dec 19 2014 This demonstrates how rows and streams might work. Scope appears to be carried along, but is unused
# since the code currently only demos if-if-else.

# - add if-else stream management (stack?). Consider if streams are global, or are compiled into args sent to
# unwind() and rewind().

# - add demo sub that deals with $scope

# http://search.cpan.org/~lembark/LinkedList-Single-v0.99.21/lib/LinkedList/Single.pm

# This works with our list of lists. Note the function is call dclone().
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

# This works with our lists of lists and may be faster than Storable.
# use Clone qw(clone);

# Using $#table works if we loop by decrementing, even if we are adding rows with push() inside the loop.

# We're decrementing so that dclone() can add new rows at the end of the list and won't effect rows which
# haven't been unwound. It's clever.

my @table;
my $rowc = 0;
# What is scope? Only for subroutines?
my $scope = 0;

main();

# aka create_scope, push_scope and so on

# $table[row=0][scope=0]->{food} = "cake";

# $table[row=0][scope=0]->{stuff} = "cake"; # new unshifted zero
# $table[row=0][scope=1]->{food} = "cake"; # zero becomes 1


sub inc_scope 
{
    my @proto = @{$_[0]};
    my @arg = @{$_[1]};

    foreach my $row (@table) # (0..$#{$table[0]})
    {
        # Use hash slice as both lvalue and value.
        my $new_scope;
        @{$new_scope}{@proto} = @{[@{$row->[0]}{@arg}]};
        # printf ("new scope:\n%s\n", Dumper($new_scope));
        unshift @{$row}, $new_scope;
        # printf ("new table row:\n%s\n", Dumper(\@table));
    }
}

sub dec_scope
{
    my @proto = @{$_[0]};
    my @arg = @{$_[1]};

    foreach my $row (@table) # (0..$#{$table[0]})
    {
        # Use hash slice as both lvalue and value.
        @{$row->[1]}{@arg} = @{$row->[0]}{@proto};
        shift @{$row};
    }
}


sub main
{
    my $in_stream = 0;

    # Initialize the scope zero table with 3 rows.
    foreach my $rowc (0..3)
    {
        $table[$rowc][0] = {var1 => "v1: $rowc",
                                 var2 => "v2: $rowc",
                                 var3 => "v3: $rowc",
                                 _stream => $in_stream};
    }

    
    my @proto = ("dog", "cat");

    # print Dumper(\@proto);

    my @arg = ("var1", "var2");
    # inc_scope(\@proto, \@arg);
    inc_scope(["dog", "cat"], ["var1", "var2"]);
    # printf ("post inc_scope:\n%s\n", Dumper(\@table));

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][0];
        if ($hr->{cat} eq "v2: 1")
        {
            $hr->{cat} = $hr->{cat} . ' cat';
        }
    }

    dec_scope(\@proto, \@arg);
    printf ("post dec_scope:\n%s\n", Dumper(\@table));

    # Split the table, ala if-stmt. I guess it is "outer" because we have a nested "inner" if statement below.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        if ($hr->{var1} eq "v1: 1" || $hr->{var1} eq "v1: 2" )
        {
            $hr->{_stream} = 'outer_if';
        }
    }

    printf ("after if stream split:\n%s\n", Dumper(\@table));

    # Rows remaining in stream zero are the else-stmt.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        if ($hr->{_stream} eq "0")
        {
            $hr->{_stream} = 'else';
        }
    }

    # Start running code on the streams
    # Outer if-stmt must run first.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        if ($hr->{_stream} eq 'outer_if')
        {
            $hr->{var1} .= "pie (outer)";
            my $newr = dclone(\@{$table[$row]});
            $newr->[$scope]->{var1} = "new row from var1 (outer)";
            push(@table, $newr);
        }
    }

    # Split the outer to create an inner if-stmt that must run second (next, now).

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        if ($hr->{_stream} eq 'outer_if' && $hr->{var2} eq "v2: 2")
        {
            $hr->{var2} .= " cheesecake (outer, pre-inner split)";
            my $newr = dclone(\@{$table[$row]});
            $newr->[$scope]->{var1} = "modified, cloned row (inner), originally var2. r:$row";
            push(@table, $newr);
        }
    }

    # printf ("post inner:\n%s\n", Dumper(\@table));

    # We can run the else now or later, it doesn't matter.

    # Seeing as _stream has text in it, I can't help but wonder if $in_stream+2 will work, or if it will even
    # do something rational.

    # It appears we don't really use streams, except that while there are active if-else statements, the two
    # (or how many ever) streams need unique values.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        if ($hr->{_stream} eq 'else')
        {
            $hr->{var1} .= "cake";
            $hr->{_stream} = $in_stream+2;
        }
    }

    printf ("post-else:\n%s\n", Dumper(\@table));

    # WTF was stname? Pretty clearly no longer used.
    # delete all the keys from stname
    # foreach my $key (keys(%stname))
    # {
    #     delete($stname{$key});
    # }

    # Merge all the streams.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        $hr->{_stream} = 0;
    }

    # A new line of deft code.
    # Add a new column. No nesting, no cloning rows.

    # for(my $row=$#table; $row >= 0; $row--)
    # {
    #     my $hr = $table[$row][$scope];
    #     $hr->{var4} = "new col $row";
    #     # No nesting or subs so no need to inc the stream.
    # }
    
    rewind();
    my $row  = $#table;
    while(my $hr = unwind())
    {
        $hr->{var4} = "new col $row";
        $row--;
    }

    printf ("final:\n%s\n", Dumper(\@table));

    exit();


} # end main


sub old_stuff
{
    my @list = (0..3);

    # foreach my $index (0..$#list)
    my $max = $#list;
    for (my $index = 0; $index <= $max; $index++)
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
}

# sub mainx
# {
#     my $unwind = init_unwind();

#     &$unwind("one");
#     &$unwind("two");
#     &$unwind("three");

# }

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

sub rewind
{
    $rowc = $#table;
}

sub unwind
{
    # printf ("uw:\n%s\n", Dumper($hr));
    # print "unwind: $rowc\n";

    # In this (simplified?) universe, the body of unwind() is an if() statement, not while(). Why would it be
    # a while()? I think it was a while() at some historical time. Maybe we'd switch to using while() if there
    # were memoized rows of data that we had to skip in order to get to a "real" row of data.

    if ($rowc >= 0)
    {
        my $hr = $table[$rowc][$scope];
        $rowc--;
        # printf("hr: %s %s\n",  ref(\\%{$hr}));
        # if (get_eenv("_memoz"))
        # {
        #     copy_view_list(); # sub above. Clears _memoz.
        #     next;
        # }
        return $hr;
    }
    return undef;
}

sub clone
{
    my $newr = dclone(\@{$table[$rowc]});
    push(@table, $newr);
    return \%{$table[$#table][$scope]};
}

# There is an existing function reset() so we have to use another name.
# Conflicting functions silently fail.
sub treset
{
    print "resetting\n";
    $rowc = $#table+1;
    $scope = 0;
}


if (0)
{
    my $in_stream = 0;

    foreach my $rowc (0..3)
    {
        $table[$rowc][0] = {var1 => "v1: $rowc", var2=> "v2: $rowc", var3 => "v3: $rowc", _stream => $in_stream};
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

    print Dumper(\@table);
    exit();
}


sub more_old_stuff
{
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
