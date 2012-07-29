#!/usr/bin/perl

use strict;
use DBI; #  qw(:sql_types);
use DBD::Pg qw(:pg_types);
use Storable qw(freeze thaw);

require "./sr_lib.pl";

main:
{
    my $host = 'localhost';
    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:Pg:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "test",
			    "stuff",
			    $dbargs);

    # Gets next available input stream, updates, commits.
    my $in_stream = sql_next_in($dbh); 
    my $out_stream = $in_stream+1;

    my $saved_data;
    my $go_flag = 1;
    my $row_count;
    my $sth_read = sql_read_prep($dbh, $in_stream);
    my $sth_write = sql_write_prep($dbh, $out_stream);
    while(my $data = sql_read($dbh, $sth_read, $in_stream))
    {
	$saved_data = $data;
	$row_count++;
	sql_write($sth_write, $data);
    }
    $sth_read->finish();
    $sth_write->finish();
    sql_inactivate_stream($dbh, $out_stream); # bench_lib.pl
    $dbh->commit();
    $dbh->disconnect();

    print "Read completed $row_count rows on stream $in_stream.\n";
    my $href = thaw($saved_data);
    foreach my $item (keys(%{$href}))
    {
	print "key:$item value:$href->{$item}\n";
    }
    
}

