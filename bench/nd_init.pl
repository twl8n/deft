#!/usr/bin/perl

# No Delete
# A variant of st_init.pl where instead of 'marked' with updates and deletes,
# records are written, but always with a unique nd_fk from the nd_keys table.
# Garbage collection needs to be added, but would presumably be quicker
# since it only happens once.

use strict;
use DBI;  # qw(:sql_types);
use DBD::Pg qw(:pg_types);

use Storable qw(freeze thaw);

require "./nd_lib.pl";

main:
{
    my $iter = 20000;
    my $commit_interval = 4000;
    my $first_in_stream = 0;
    my $number_of_streams = 3; # you can have n-1 copies of mp_proc.pl
    my $host = 'localhost';

    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:Pg:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "test",
			    "stuff",
			    $dbargs);

    # Clean up before starting.
    sql_start_clean($dbh);

    $dbh->commit();

    my $st_id = sql_init_streams($dbh, 3);
    print "writing st_id:$st_id\n";

    $dbh->commit();

    my %dhash;
    $dhash{one} = "this is small data payload 1 of 3";
    $dhash{two} = "this is small data payload 2 of 3";
    $dhash{three} = "this is small data payload 3 of 3";
    my $data = freeze(\%dhash);

    my $sth = sql_write_prep($dbh, $st_id);
    
    for(my $xx=0; $xx<($iter+1); $xx++)
    {
	sql_write($sth, $data); # see sql_write_prep above.
	if (($xx % $commit_interval == 0) && $xx > 0)
	{
	    print "Commiting after $xx records\n";
	    $dbh->commit();
	    $sth = sql_write_prep($dbh, $st_id);
	}
    }
    $sth->finish();
    sql_inactivate_stream($dbh, $st_id); # bench_lib.pl
    $dbh->commit();
    print "Write $iter done.\n";
    $dbh->disconnect();
}


