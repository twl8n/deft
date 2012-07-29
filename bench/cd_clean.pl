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

    # Clean up before starting.
    $dbh->do("delete from stream_flags");
    $dbh->do("delete from stream_row");

    $dbh->commit();
    $dbh->disconnect();
}
