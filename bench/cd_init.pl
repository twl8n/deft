#!/usr/bin/perl

# Combined Data
# Uses stream_row, one row per record, uses column 'marked', very similar to sr_lib.pl
# However, now we freeze up many records so the database does less work.


use strict;
use DBI;  # qw(:sql_types);
use DBD::Pg qw(:pg_types);

use Storable qw(freeze thaw);

require "./cd_lib.pl";

main:
{
    my $iter = 4;
    my $cache_size = 5000;
    my $commit_interval = 1;
    my $number_of_streams = 3;

    my $host = 'localhost';
    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:Pg:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "test",
			    "stuff",
			    $dbargs);

    
    #
    # If you want a clean start, run cd_clean.pl
    #

    my $out_stream = sql_init_streams($dbh, $number_of_streams);
    print "Writing to stream:$out_stream\n";

    $dbh->commit();

    if (0)
    {
	open(ONE, "| /usr/bin/time -v ./cd_proc.pl > `mktemp -p ./` 2>&1");
	open(TWO, "| /usr/bin/time -v ./cd_proc.pl > `mktemp -p ./` 2>&1");
    }


    my %dhash;
    $dhash{one} = "this is small data payload 1 of 3";
    $dhash{two} = "this is small data payload 2 of 3";
    $dhash{three} = "this is small data payload 3 of 3";

    my @big_arr;
    for(my $xx=0; $xx<$cache_size; $xx++)
    {
	%{$big_arr[$xx]} = %dhash;
    }

    my $data = freeze(\@big_arr);
    print "Done freezing $cache_size\n";
    for(my $xx=0; $xx<$iter; $xx++)
    {
	sql_write($dbh, $out_stream, $data);
	if ((($xx+1) % $commit_interval == 0) && $xx > 0)
	{
	    printf("Commiting after %d records\n", $xx+1);
	    $dbh->commit();
	}
    }
    $dbh->commit();
    # $sth->finish();
    sql_inactivate_stream($dbh, $out_stream); # bench_lib.pl
    $dbh->commit();
    print "Write $iter with $cache_size done.\n";
    $dbh->disconnect();
}


