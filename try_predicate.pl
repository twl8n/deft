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

# What is scope? Only for subroutines? (Apparently only for subs since it isn't used in this demo.)
my $scope = 0;

main();

# aka create_scope, push_scope and so on

# $table[row=0][scope=0]->{food} = "cake";

# $table[row=0][scope=0]->{stuff} = "cake"; # new unshifted zero
# $table[row=0][scope=1]->{food} = "cake"; # zero becomes 1

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

    # Split the table, ala if-stmt. I guess it is "outer" because we have a nested "inner" if statement below.
    # for(my $row=$#table; $row >= 0; $row--)
    # {
    #     my $hr = $table[$row][$scope];
    #     if ($hr->{var1} eq "v1: 1" || $hr->{var1} eq "v1: 2" )
    #     {
    #         $hr->{_stream} = 'outer_if';
    #     }
    # }

    
    unwind();

    exit();

    # Rows where _stream eq '' are else.

    # Run the if records first, although order doesn't matter.  Cool side effecto of cloning: The new row
    # inherits the _stream, so new rows won't run by the else code below.

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

    printf ("post outer:\n%s\n", Dumper(\@table));

    # This isn't an inner if, just a second following if block based on the same outer_if predicate.

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
        if ($hr->{_stream} ne 'outer_if')
        {
            $hr->{var1} .= "cake(else)";
        }
    }

    printf ("post-else:\n%s\n", Dumper(\@table));

    # We don't need to "merge" all the streams, but if we want to reuse a predicate column it is smart to zero it out.

    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        $hr->{_stream} = 0;
    }

    printf ("final:\n%s\n", Dumper(\@table));

    exit();


} # end main

# Create new column, which must happen for all rows
sub newc
{
    for(my $row=$#table; $row >= 0; $row--)
    {
        my $hr = $table[$row][$scope];
        foreach my $newcol (@_)
        {
            $hr->{$newcol} = '';
        }
    }
}


sub unwind
{
    # my $fref = $_[0];
    my $row;
    my @exec; # list of subroutine pointers.
    my $hr;
    
    # Some kind of magic happens where assigning the vars in fref changes @table. I wonder how that happens?

    my $fref = sub
    { 
        no strict;
        if ($var1 eq "v1: 1" || $var1 eq "v1: 2")
        {
            $_stream = 'outer_if';
        }
        print Dumper($hr);

    };
    push(@exec, $fref);

    $fref = sub 
    {
        no strict;
        $sequence = 1;
        print "var1: $var1\n";
        $var1 .= "stuff";
    };
    push(@exec, $fref);

    $fref = sub
    {
        no strict;
        print Dumper($hr);
    };
    push(@exec, $fref);


    sub print_row
    {
        print "row: $row\n";
    }

    # Create new cols in the current row, and make variables in the local scope for those columns.

    # newr({'var1' => 'value1', 'var2' => 'value2' ...})

    # This isn't really what is needed for something like read_tab_data()
    sub newr
    {
        my %args = @_;
        # Probably actually meant clone() as below, and not dclone()
        # my $newr = dclone(\@{$table[$row]});

        # clone() copies the current row, pushes it onto the end of $table[$rowc] and returns the reference of
        # the new row. We can change the new row using this new hash ref.
        my $new_hr = clone();
        foreach my $key (keys(%args))
        {
            # $newr->[$scope]->{$key} = $args{$key};
            $new_hr->{$key} = $args{$key};
        }
        # push(@table, $newr);
    }

    print "zero: $_[0]\n";

    foreach my $fref (@exec)
    {
        print "have fref: $fref\n";
        for ($row=$#table; $row >= 0; $row--)
        {
            $hr = $table[$row][$scope];
            {
                no strict;
                foreach my $key (keys(%{$hr}))
                {
                    $$key = $hr->{$key};
                }
                &$fref();
                foreach my $key (keys(%{$hr}))
                {
                    $hr->{$key} = $$key;
                }
            }
        }
    }
}

# read_tab_data("./demo.dat", 'sequence', 'make', 'model', 'displacement','units');
sub read_tab_data
{
    my $data_file = shift(@_); # first arg is data file $_[0]
    my @va = @_; # remaining args are column names.
    
    my($temp);
    my @fields;
    
    # Crossmultiply incoming stream with new input.  Normally, there is only one incoming record.
    
    my $log_flag = 0;

    if (! open(IN, "<",  $data_file))
    {
        if (! $log_flag)
        {
            write_log("Error: Can't open $data_file for reading");
            $log_flag = 1;
        }
        # At least in the real Deft simply exiting here leaves all the downstream ancestors hanging
        # around. rewind, don't exit.  

        # exit(1);
    }
    else
    {
        # Need to make a copy of the orig record for each input record. Either delete the orig or append one
        # of the input recs onto it.
        my $first = 1;
        while ($temp = <IN>)
        {
            # Don't use split because Perl will truncate the returned array due to an undersireable feature
            # where arrays returned and assigned have null elements truncated.

            # Also, make sure there is a terminal \n which makes the regex both simpler and more robust.
		
            if ($temp !~ m/\n$/)
            {
                $temp .= "\n";
            }

            if (! $first)
            {
                # dup_insert(curr_rec());
                my $hr = clone();
                set_ref_eenv($hr);
            }
            $first = 0;
            for (my $xx=0; $xx<=$#va && $temp; $xx++)
            {
                # The regex needs an if() test.  If there are too few
                # columns, the missing columns will have the value of the
                # last column that existed. This is the old regex $1
                # problem.
                    
                $temp =~ s/(.*?)[\t\n]//;
                set_eenv($va[$xx], $1);
            }
        }
    }
    close(IN);
    # unwind($func);
}


# I guess $rowc is a global. Should this be inside unwind()?
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
