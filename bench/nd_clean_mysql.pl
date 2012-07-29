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

require "./nd_lib_mysql.pl";

main:
{
    my $iter = 20000;
    my $commit_interval = 4000;
    my $first_in_stream = 0;
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
    $dbh->disconnect();
}
