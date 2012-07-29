#!/usr/bin/perl

# cd_race1.pl is part one of a race condition test.
# run cd_clean.pl
# run cd_race1.pl and wait for "one finishes..."
# in another terminal window run cd_race2.pl
# When both finish, you'll see that both were going to try to
# use the same outstream, and that the reader_id is for cd_race2.pl
# 


use strict;
use DBI;  # qw(:sql_types);
use DBD::Pg qw(:pg_types);

use Storable qw(freeze thaw);

require "./cd_lib.pl";

main:
{
    my $iter = 20;
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

    (my $st_id, $out_stream) = sql_race_one($dbh);

    print "st_id:$st_id os:$out_stream\n";

    sleep(10);

    sql_check_st_id($dbh, $st_id);
    
    $dbh->commit();
    $dbh->disconnect();
}


