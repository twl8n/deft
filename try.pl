#!/usr/bin/perl

use strict;
use Data::Dumper;

# http://search.cpan.org/~lembark/LinkedList-Single-v0.99.21/lib/LinkedList/Single.pm

# This works with our list of lists. Note the function is call dclone().
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

# This works with our lists of lists and may be faster than Storable.
# use Clone qw(clone);

{
    my $in_stream = 0;

    my @table;

    foreach my $rowc (0..3)
    {
        $table[$rowc][0] = {var1 => "v1: $rowc", var2=> "v2: $rowc", var3 => "v3: $rowc", _stream => $in_stream};
    }

    # split, ala if-stmt

    my $max = $#table;
    my %stname;
    foreach my $row (0.. $max)
    {
        my $hr = $table[$row][0];
        if ($hr->{var1} eq "v1: 1" || $hr->{var1} eq "v1: 2" )
        {
            $hr->{_stream} = 'outer_if';
            $stname{outer_if} = 1;
        }
    }

    # split, remainder ala else-stmt

    $max = $#table;
    foreach my $row (0.. $max)
    {
        my $hr = $table[$row][0];
        if ($hr->{_stream} eq "0")
        {
            $hr->{_stream} = 'else';
            $stname{else} = 1;
        }
    }

    # start running code on the streams

    # We can run the else now or later, it doesn't matter.
    $max = $#table;
    foreach my $row (0..$max)
    {
        my $hr = $table[$row][0];
        if ($hr->{_stream} eq 'else')
        {
            $hr->{var1} .= "cake";
            $hr->{_stream} = $in_stream+2;
        }
    }

    # inner oute if-stmt must run first.
    $max = $#table;
    foreach my $row (0.. $max)
    {
        my $hr = $table[$row][0];
        if ($hr->{_stream} eq 'outer_if')
        {
            $hr->{var1} .= "pie";
            my $newr = dclone(\@{$table[$row]});
            $newr->[0]->{var1} = "new row from var1";
            push(@table, $newr);
        }
    }

    # inner if-stmt must run second

    $max = $#table;
    foreach my $row (0.. $max)
    {
        my $hr = $table[$row][0];
        if ($hr->{_stream} eq 'outer_if' && $hr->{var2} eq "v2: 2")
            {
            $hr->{var2} .= " cheesecake";
            my $newr = dclone(\@{$table[$row]});
            $newr->[0]->{var1} = "new row from var2";
            push(@table, $newr);
        }
    }

    # delete all the keys from stname
    foreach my $key (keys(%stname))
    {
        delete($stname{$key});
    }

    # Merge all the streams.
    $max = $#table;
    foreach my $row (0..$max)
    {
        my $hr = $table[$row][0];
        $hr->{_stream} = 0;
    }

    # A new line of deft code.
    # Add a new column. No nesting, no cloning rows.

    $max = $#table;
    foreach my $row (0..$max)
    {
        my $hr = $table[$row][0];
        $hr->{var4} = "new col $row";
        
        # No nesting or subs so no need to inc the stream.
    }
    
    printf ("ff: %s\n", Dumper(\@table));


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

sub init_unwind
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

