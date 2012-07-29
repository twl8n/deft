#!/usr/bin/perl

# Multi Process
# A misnomer, but the name stuck. Based on sr_init.pl,
# but creates a table for each stream.


use strict;
use DBI;  # qw(:sql_types);
use DBD::Pg qw(:pg_types);

use Storable qw(freeze thaw);

require "./mp_lib_mysql.pl";

main:
{
    my $iter = 20000;
    my $commit_interval = 4000;
    my $number_of_streams = 3; # you can have n-1 copies of mp_proc.pl
    my $host = 'localhost';

    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:mysql:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "",
			    "",
			    $dbargs) || die "connect error:\n$DBI::errstr\n";

    # Clean up before starting.
    sql_start_clean($dbh);

    $dbh->commit();

    my $out_stream = sql_init_streams($dbh, 3);
    print "writing out_stream:$out_stream\n";

    $dbh->commit();
    
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


