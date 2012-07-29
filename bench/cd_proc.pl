#!/usr/bin/perl

use strict;
use DBI; #  qw(:sql_types);
use DBD::Pg qw(:pg_types);
use Storable qw(freeze thaw);

require "./cd_lib.pl";

main:
{
    my $commit_interval = 4;

    my $host = 'localhost';
    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:Pg:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "test",
			    "stuff",
			    $dbargs);

    # Gets next available input stream, updates, commits.
    (my $in_stream, my $out_stream) = sql_next_in($dbh); 

    if (! $out_stream)
    {
	print "No output stream. This should never happen. Exiting.\n";
	$dbh->commit();
	$dbh->disconnect();
	exit(1);
    }

    my $saved_data;
    my $go_flag = 1;
    my $row_count = 0;

    # 
    # sql_read() commits after reading a block of records!
    # 
    my @records = sql_read($dbh, $in_stream);
    while($#records > -1)
    {
	foreach my $data (@records)
	{
	    $saved_data = $data;
	    $row_count++;
	    sql_write($dbh, $out_stream, $data); 
	}
	@records = sql_read($dbh, $in_stream);
    }

    sql_inactivate_stream($dbh, $out_stream); # bench_lib.pl
    $dbh->commit();
    $dbh->disconnect();

    print "Read completed $row_count rows on stream $in_stream.\n";
    my $href = thaw($saved_data);
    my %one_record = %{$href->[1]};

    printf("Cached records/row:%d\n", $#{$href}+1);
    foreach my $item (keys(%one_record))
    {
	print "key:$item value:$one_record{$item}\n";
    }
    
}

