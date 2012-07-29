#!/usr/bin/perl

# cd_race2_fixed.pl is part two of a race condition test.
# See the instructions in cd_race1_fixed.pl
# 
# When both finish, you'll see that they correctly
# use different output streams.
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

    # start cd_race1.pl first!
    
    $dbh->commit();

    (my $st_id, my $out_stream) = sql_race_two_fixed($dbh);

    print "st_id:$st_id os:$out_stream\n";

    sql_check_st_id($dbh, $st_id);

    $dbh->commit();
    $dbh->disconnect();
}


