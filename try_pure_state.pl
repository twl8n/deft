#!/usr/bin/perl

use strict;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# Usage: ./try_pure_state.pl

my @table;

main();

sub main
{
    $| = 1;
    read_data("states.dat", 'order', 'edge', 'choice', 'test', 'func', 'next');

    my $curr_state = 'page_search';
    my $do_next = 0;
    my $choice = '';
    while (1)
    {
        if (! $do_next)
        {
            print "Current state: $curr_state\n";
            foreach my $hr (@table)
            {
                if (($hr->{edge} eq $curr_state) && $hr->{choice})
                {
                    print "$hr->{test}\n";
                }
            }
            print "Enter one:";
            $choice = <>;
            chomp($choice);
        }
        else
        {
            print "Auto next: state: $curr_state choice: $choice (press return to continue)";
            my $temp = <>;
        }
        my $last_flag = 0;
        foreach my $hr (@table)
        {
            if (($hr->{edge} eq $curr_state) && (($hr->{test} eq $choice) || ($hr->{test} eq 'true')))
            {
                $choice = $hr->{func};
                $last_flag = 1;
                if ($hr->{func} ne 'null')
                {
                    print "Dispatch function: $hr->{func}\n";
                }
                if ($hr->{next} ne 'wait')
                {
                    $curr_state = $hr->{next};
                    $do_next = 1;
                }
                else
                {
                    $do_next = 0;
                }
            }
            if ($last_flag)
            {
                last;
            }
        }
    }
}


sub read_data
{
    my $data_file = shift(@_);
    my @va = @_; # remaining args are column names, va mnemonic for variables.

    print "df: $data_file\n";
    my($temp);
    my @fields;
    
    my $log_flag = 0;

    if (! open(IN, "<",  $data_file))
    {
        if (! $log_flag)
        {
            print ("Error: Can't open $data_file for reading\n");
            $log_flag = 1;
        }
    }
    else
    {
        while ($temp = <IN>)
        {
            my $new_hr;

            if ($temp =~ m/^\s*#/)
            {
                # We have a comment, ignore this line.
                next;
            }

            # Don't use split because Perl will truncate the returned array due to an undersireable feature
            # where arrays returned and assigned have null elements truncated.

            # Also, make sure there is a terminal \n which makes the regex both simpler and more robust.

            if ($temp !~ m/\n$/)
            {
                $temp .= "\n";
            }

            # Get all the fields before we start so the code below is cleaner, and we want all the line
            # splitting regex to happen here so we can swap between tab-separated, whitespace-separated, and
            # whatever.

            my @fields;
            while ($temp =~ s/^(.*?)(\s+|\n)//smg)
            {
                # Clean up "$var" and "func()" to be "var" and "func".
                my $raw = $1;
                $raw =~ s/\(\)//;
                $raw =~ s/^\$//;
                push(@fields, $raw);
            }
            
            for (my $xx=0; $xx<=$#va; $xx++)
            {
                $new_hr->{$va[$xx]} = $fields[$xx];
            }
            push(@table, $new_hr);
        }
    }
    close(IN);
}
