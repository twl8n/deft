#!/usr/bin/perl

use strict;
use DBI; #  qw(:sql_types);
use DBD::Pg qw(:pg_types);
use Storable qw(freeze thaw);

require "./nd_lib_mysql.pl";

main:
{
    my $host = 'localhost';

    my $dbargs = {AutoCommit => 0, PrintError => 0};
    my $connect_string = "dbi:mysql:dbname=test;host=$host;";
    my $dbh =  DBI->connect($connect_string,
			    "",
			    "",
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
    my $row_count;
    my $sth_read = sql_read_prep($dbh, $in_stream);
    my $sth_write = sql_write_prep($dbh, $out_stream);

    #
    # Read and write must occur in lockstep, so the commit
    # has to be here instead of buried in sql_read().
    # Really dumb things happen because sql_read() starts off by
    # getting a new nd_fk and therefore needs a commit, and therefore
    # zero records are written to the first output nd_fk.
    #

    my $data = 1;
    while($data)
    {
	($data, my $commit_flag) = sql_read($dbh, $sth_read, $in_stream);
	if ($data)
	{
	    $saved_data = $data;
	    $row_count++;
	    if ($commit_flag)
	    {
		$dbh->commit();
		$sth_write = sql_write_prep($dbh, $out_stream);
	    }
	    sql_write($sth_write, $data);
	}
    }
    $sth_read->finish();
    $sth_write->finish();
    # sql_read_clean($dbh, $in_stream);         # drop the input stream table
    sql_inactivate_stream($dbh, $out_stream); # tell any readers that we're done writing.
    
    $dbh->commit();
    $dbh->disconnect();

    print "Read completed $row_count rows on stream $in_stream.\n";
    printf("length of saved_data:%d\n", length($saved_data));
    my $href = thaw($saved_data);
    foreach my $item (keys(%{$href}))
    {
	print "key:$item value:$href->{$item}\n";
    }
}

