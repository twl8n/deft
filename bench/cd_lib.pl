use strict; 
use DBD::Pg qw(:pg_types);

sub sql_prototype
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sql = "";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { 	die "doq $q_name 1\n$DBI::errstr\n";  }
    $sth->execute();
    if ($dbh->err()) { 	die "doq $q_name 2\n$DBI::errstr\n";  }
}

sub sql_read
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sr_in = $_[1];

    my $sql = "select data from stream_row where sr_in=$sr_in and marked=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$dbi::errstr\n"; }

    my $go_flag = 1;
    my $have_record = 0;
    my @records; 
    while (! $have_record && $go_flag)
    {
	if (sql_mark($dbh, $sr_in))
	{
	    # select marked records from stream_row
	    my $rows = $sth->execute();
	    if ($sth->err()) { die "$q_name 2\n$dbi::errstr\n"; }
	    if ($rows > 0)
	    {
		while ((my $data) = $sth->fetchrow_array())
		{
		    push(@records, $data);
		}
	    }
	    if ($#records > -1)
	    {
		$have_record = 1;
		# delete marked records in stream_row
		sql_update_stream($dbh, $sr_in);
		$dbh->commit();
		# print "Commiting\n";
	    }
	}
	else
	{
	    # select is_active from stream_flags, select unmarked from stream_row
	    $go_flag = upstream_done($dbh, $sr_in);
	}
    }
    return @records;
}

#
# Init a family of streams, all active, none have readers yet.
# Stream ids are now generated from a sequence to make sure they 
# are unique (and won't be repeated).
#
sub sql_init_streams
{
    my $q_name = "sql_init_streams";
    my $dbh = $_[0];
    my $stream_count = $_[1]; 

    my $sql = "insert into stream_flags (is_active, reader_id) values (1,'none')";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    
    my $st_sql = "select currval('st_seq')";
    my $st_sth = $dbh->prepare($st_sql);
    if ($dbh->err()) { die "$q_name 3\n$st_sql\n$DBI::errstr\n"; }

    my $sf_pk;
    my @id_array;
    for(my $xx=0; $xx<=$stream_count; $xx++)
    {
	$sth->execute();     # insert stream_flags record
	if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
	$st_sth->execute();  # get the new sf_pk (of the new record)
	if ($dbh->err()) { die "$q_name 4\n$st_sql\n$DBI::errstr\n"; }
	($sf_pk) = $st_sth->fetchrow_array();

	push(@id_array, $sf_pk);
    }
    $sth = $dbh->prepare("update stream_flags set sf_in=?,sf_out=? where sf_pk=?");
    
    # Set all the out streams except the last (which is set below to zero)
    for(my $xx=0; $xx<$#id_array; $xx++)
    {
	$sth->execute($id_array[$xx], $id_array[$xx+1], $id_array[$xx]);
    }
    # Loop does xx+1, so we have to special case the last record.
    $sth->execute($id_array[$#id_array], 0, $id_array[$#id_array]);
    
    # The head process owns the zeroth record.
    $dbh->do("update stream_flags set reader_id='head' where sf_in=$id_array[0]");
    
    # return the output stream (sf_out) of the zeroth record.
    return $id_array[1];
}

sub sql_next_in
{
    my $q_name = "sql_next_in";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";
    my $reader_id = "$hostname:$ppid";

    my $sth;

    my $sf_pk = 0;
    my $rows = 0;
    my $sf_out = 0;
    my $sf_in = 0;
    my $first_done = 0;
    while (! $sf_pk) #  || ! $out_stream)
    {
	if ($first_done)
	{
	    # sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select sf_pk,sf_in,sf_out from stream_flags where reader_id='none' order by sf_pk limit 1");
	$sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	($sf_pk, $sf_in, $sf_out) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("delete from stream_flags where sf_pk=$sf_pk");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$rows = $sth->execute();

	$dbh->commit();
	
	if ($rows == 0)
	{
	    #
	    # Even if we got an sf_pk, if we are unable to delete, then another
	    # process got there first and we don't really have an sf_pk.
	    #
	    $sf_pk = 0;
	}
	elsif ($sf_pk)
	{
	    #
	    # If things look good, insert a proper stream_flag record to replace the one we deleted.
	    # The sf_pk will be different, so get it from the sequence.
	    # 

	    $sth = $dbh->prepare("insert into stream_flags (is_active,sf_in,sf_out,reader_id)
				  values (1,$sf_in,$sf_out,'$reader_id')");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    $sth->finish();
	    $dbh->commit();

	    #$sth = $dbh->prepare("select currval('st_seq')");
	    #if ($dbh->err()) { die "doq $q_name 5\n$DBI::errstr\n";  }
	    #$rows = $sth->execute();
	    #if ($dbh->err()) { die "doq $q_name 6\n$DBI::errstr\n";  }
	    #($sf_pk) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $sf_pk\n";
    return ($sf_in, $sf_out);
}


sub sql_race_one
{
    my $q_name = "sql_race_one";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";

    my $sf_pk;
    my $rows = 0;
    my $sth;

    #
    # see sr_init.pl, sf_pk of zero must be illegal.
    #
    my $sf_out;
    my $first_done = 0;
    while (! $sf_pk || ! $sf_out)
    {
	if ($first_done)
	{
	    sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select sf_pk from stream_flags where reader_id='none' order by sf_pk limit 1");
	$rows = $sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	($sf_pk) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("update stream_flags set reader_id='$hostname:$ppid' where sf_pk=$sf_pk");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$sth->execute();

	print "one finishes select and update. sf_pk:$sf_pk\n";
	sleep(3); # Give two time to select and update

	$dbh->commit();
	
	# try to get the sf_pk we might have just set
	if ($sf_pk)
	{
	    $sth = $dbh->prepare("select sf_pk,sf_out from stream_flags where sf_pk=$sf_pk and reader_id='$hostname:$ppid'");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $rows = $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    ($sf_pk, $sf_out) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $sf_pk\n";
    return ($sf_pk, $sf_out);
}

sub sql_race_two
{
    my $q_name = "sql_race_two";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";

    my $sf_pk;
    my $rows = 0;
    my $sth;

    #
    # see sr_init.pl, sf_pk of zero must be illegal.
    #
    my $sf_out;
    my $first_done = 0;
    while (! $sf_pk || ! $sf_out)
    {
	if ($first_done)
	{
	    sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select sf_pk from stream_flags where reader_id='none' order by sf_pk limit 1");
	$rows = $sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	($sf_pk) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("update stream_flags set reader_id='$hostname:$ppid' where sf_pk=$sf_pk");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$sth->execute();

	print "two finishes select and update. sf_pk:$sf_pk\n";
	sleep(6);

	$dbh->commit();
	
	# try to get the sf_pk we might have just set
	if ($sf_pk)
	{
	    $sth = $dbh->prepare("select sf_pk,sf_out from stream_flags where sf_pk=$sf_pk and reader_id='$hostname:$ppid'");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $rows = $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    ($sf_pk, $sf_out) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $sf_pk\n";
    return ($sf_pk, $sf_out);
}

sub sql_race_one_fixed
{
    my $q_name = "sql_race_one_fixed";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";
    my $reader_id = "$hostname:$ppid";

    my $sf_pk;
    my $rows = 0;
    my $sth;

    #
    # see sr_init.pl, sf_pk of zero must be illegal.
    #
    my $sf_out;
    my $first_done = 0;
    while (! $sf_pk || ! $sf_out)
    {
	if ($first_done)
	{
	    sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select sf_pk,sf_out from stream_flags where reader_id='none' order by sf_pk limit 1");
	$sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	($sf_pk, $sf_out) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("delete from stream_flags where sf_pk=$sf_pk");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$rows = $sth->execute();

	print "one finishes select and delete. sf_pk:$sf_pk rows:$rows\n";
	sleep(3); # Give two time to select and delete

	$dbh->commit();
	
	if ($rows == 0)
	{
	    $sf_pk = 0;
	}
	elsif ($sf_pk)
	{
	    $sth = $dbh->prepare("insert into stream_flags (sf_out,reader_id) values ($sf_out,'$reader_id')");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    $sth->finish();

	    $sth = $dbh->prepare("select currval('st_seq')");
	    if ($dbh->err()) { die "doq $q_name 5\n$DBI::errstr\n";  }
	    $rows = $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 6\n$DBI::errstr\n";  }
	    ($sf_pk) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $sf_pk\n";
    return ($sf_pk, $sf_out);
}

sub sql_race_two_fixed
{
    my $q_name = "sql_race_two_fixed";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";
    my $reader_id = "$hostname:$ppid";

    my $sf_pk;
    my $rows = 0;
    my $sth;

    #
    # see sr_init.pl, sf_pk of zero must be illegal.
    #
    my $sf_out;
    my $first_done = 0;
    while (! $sf_pk || ! $sf_out)
    {
	if ($first_done)
	{
	    sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select sf_pk,sf_out from stream_flags where reader_id='none' order by sf_pk limit 1");
	$sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	($sf_pk, $sf_out) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("delete from stream_flags where sf_pk=$sf_pk");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$rows = $sth->execute();

	print "two finishes select and delete. sf_pk:$sf_pk rows:$rows\n";
	sleep(6);

	$dbh->commit();

	if ($rows == 0)
	{
	    $sf_pk = 0;
	}
	elsif ($sf_pk)
	{
	    $sth = $dbh->prepare("insert into stream_flags (sf_out,reader_id) values ($sf_out,'$reader_id')");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    $sth->finish();

	    $sth = $dbh->prepare("select currval('st_seq')");
	    if ($dbh->err()) { die "doq $q_name 5\n$DBI::errstr\n";  }
	    $rows = $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 6\n$DBI::errstr\n";  }
	    ($sf_pk) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $sf_pk\n";
    return ($sf_pk, $sf_out);
}


#
# After the last data has been written to a stream, inactivate it.
# This is "inactive" in the sense that the writer is finished writing.
# The reader may still be reading from this stream.
#

sub sql_inactivate_stream
{
    my $q_name = "inactivate_stream";
    my $dbh = $_[0];
    my $sf_out = $_[1]; # writer inactivates its output stream after last write

    my $sql = "update stream_flags set is_active=0 where sf_out=$sf_out";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_write
{
    my $q_name = "sql_write";
    my $dbh = $_[0];
    my $sr_in = $_[1];
    my $data = $_[2];

    my $sql = "insert into stream_row (sr_in,data,marked) values ($sr_in,?,0)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->bind_param(1,$data, { pg_type => PG_BYTEA });
    if ($sth->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    $sth->execute();
    if ($sth->err()) { die "$q_name 3\n$DBI::errstr\n"; }
}

# Move input stream records to read stream with an update.
sub sql_mark
{
    my $q_name = "sql_mark";
    my $dbh = $_[0];
    my $sr_in = $_[1];   # input stream 

    my $sql = "update stream_row set marked=1 where sr_in=$sr_in";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    if ($rows > 0)
    {
	print "marked:$rows\n";
	return 1;
    }
    return 0;
}

# delete records we've read
sub sql_update_stream
{
    my $q_name = "sql_update_stream";
    my $dbh = $_[0];
    my $sr_in = $_[1]; # read stream (intermediate)
    
    my $sql = "delete from  stream_row where sr_in=$sr_in and marked=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    if ($rows > 0)
    {
	print "upd:$rows\n";
    }
}

# Assume the writer starts before the reader, so there 
# won't be a case of not finding a stream_flag record.

sub upstream_done
{
    my $q_name = "upstream_done";
    my $dbh = $_[0];
    my $sf_in = $_[1]; # reader's input stream

    my $sql = "select is_active from stream_flags where sf_out=$sf_in and is_active=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $flag_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    $sql = "select sr_in from stream_row where sr_in=$sf_in and marked <> 1 limit 1";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    my $data_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    
    if ($flag_rows == 0 && $data_rows == 0)
    {
 	return 0;
    }
    return 1;
}


1;
