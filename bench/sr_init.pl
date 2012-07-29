#!/usr/bin/perl

# Stream Row
# Uses stream_row, one row per record, uses column 'marked'
# Fairly simple, and what others are based on.


use strict;
use DBI;  # qw(:sql_types);
use DBD::Pg qw(:pg_types);

use Storable qw(freeze thaw);

require "./sr_lib.pl";

main:
{
    my $iter = 20000;
    my $commit_interval = 4000;
    my $number_of_streams = 3;

    my $host = 'localhost';
    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:Pg:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "test",
			    "stuff",
			    $dbargs);

    # Clean up before starting.
    $dbh->do("delete from stream_flags");
    $dbh->do("delete from stream_row");

    
    #
    # create streams. Start with st_id of one, not zero.
    # Zero is a headache for various reasons.
    #

    my @id_list;
    for(my $xx=1; $xx<=$number_of_streams; $xx++)
    {
	push(@id_list,$xx);
    }
    sql_init_streams($dbh, \@id_list);

    $dbh->commit();

    my $out_stream = $id_list[0];

    my %dhash;
    $dhash{one} = "this is small data payload 1 of 3";
    $dhash{two} = "this is small data payload 2 of 3";
    $dhash{three} = "this is small data payload 3 of 3";
    my $data = freeze(\%dhash);

    my $sth = sql_write_prep($dbh, $out_stream);
    
    for(my $xx=0; $xx<($iter+1); $xx++)
    {
	sql_write($sth, $data); # see sql_write_prep above.
	if (($xx % $commit_interval == 0) && $xx > 0)
	{
	    print "Commiting after $xx records\n";
	    $dbh->commit();
	}
    }
    $sth->finish();
    sql_inactivate_stream($dbh, $out_stream); # bench_lib.pl
    $dbh->commit();
    print "Write $iter done.\n";
    $dbh->disconnect();
}


