#!/opt/local/bin/perl

use strict;
use Data::Dumper;
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

{
    my @table;
    foreach my $row (0..3)
    {
        $table[$row][0] = {var1 => "v1: $row", var2=> "v2: $row", var3 => "v3: $row"};
    }

    printf "first: %s\n", Dumper(\@table);

    foreach my $row (0..$#table)
    {
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

