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

sub sql_start_clean
{
    my $q_name = "sql_clean_start";
    my $dbh = $_[0];
    my $sql = "select st_id from stream_flags";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { 	die "doq $q_name 1\n$DBI::errstr\n";  }
    $sth->execute();
    if ($dbh->err()) { 	die "doq $q_name 2\n$DBI::errstr\n";  }

    
    my @st_id_list;
    while ((my $st_id) = $sth->fetchrow_array())
    {
	push(@st_id_list, $st_id);
    }
    $sth->finish();
    foreach my $st_id (@st_id_list)
    {
	if ($st_id)
	{
	    $dbh->begin_work();
	    $sth = $dbh->prepare("drop table stream_row_$st_id");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $sth->execute();
	    if ($dbh->err()) { warn "doq $q_name 4\n$DBI::errstr\n";  }
	    $dbh->commit();
	}
    }

    $dbh->do("delete from stream_flags");
    # $dbh->do("delete from stream_row");
}

sub sql_read
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sth = $_[1];
    my $in_stream = $_[2];

    my $go_flag = 1;
    my $have_record = 0;
    my $data = undef;
    while (! $have_record && $go_flag)
    {
	#
	# MySQL must commit to see other transactions results
	# If this is the only commit in this loop, *proc*.pl will deadlock.
	#
	#$dbh->commit(); 
        if (($sth->{Active}) && (($data) = $sth->fetchrow_array()))
        {
            $have_record = 1;
        }
        else
        {
            # delete marked records
            sql_update_stream($dbh, $in_stream);
            if (sql_mark($dbh, $in_stream))
            {
                # select marked records
                $go_flag = sql_read_execute($sth);
		$dbh->commit();
            }
            else
            {
                # is the stream inactive, are there any unmarked records
                $go_flag = upstream_done($dbh, $in_stream);
            }
        }
    }
    return $data;
}

sub sql_read_prep
{
    my $q_name = "sql_read_prep";
    my $dbh = $_[0];
    my $st_id = $_[1]; # reader's read_stream

    my $sql = "select data from stream_row_$st_id where st_id_fk=$st_id and marked=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$dbi::errstr\n"; }
    return $sth; 
}

# Read records from the intermediate read stream.
# Check upstream to see if we should continue.
sub sql_read_execute
{
    my $q_name = "sql_read_execute";
    my $sth = $_[0];
    my $rows = $sth->execute(); # reads read_stream 
    if ($sth->err()) { die "$q_name 2\n$dbi::errstr\n"; }
    if ($rows > 0)
    {
	return 1;
    }
    else
    {
	return 0;
    }
}

sub sql_read_fetch
{
    my $q_name = "sql_read_fetch";
    my $sth = $_[0];
    my $data;
    if (($data) = $sth->fetchrow_array())
    {
	return $data;
    }
    else
    {
	return undef;
    }
}

#
# Create a table for this stream
# Tables must exist before we commit the stream_flag records
# since processes may be polling the stream_flag table looking
# for streams to read. The read relies on the table existing.
#

sub sql_ct
{
    my $q_name = "sql_ct";
    my $dbh = $_[0];
    my $st_id = $_[1]; 
    
    $dbh->do("create table stream_row_$st_id (
		st_id_fk integer,
		marked integer,
		data blob)");
    # ) TYPE=InnoDB");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }

    $dbh->do("create index st_$st_id on stream_row_$st_id (st_id_fk)");
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    $dbh->do("create index ma_$st_id on stream_row_$st_id (marked)");
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }

    $dbh->do("create index stma_$st_id on stream_row_$st_id (st_id_fk,marked)");
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
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
    
    my $st_sql = "select max(st_id) from stream_flags";
    my $st_sth = $dbh->prepare($st_sql);
    if ($dbh->err()) { die "$q_name 3\n$st_sql\n$DBI::errstr\n"; }

    my $st_id;
    my @id_array;
    for(my $xx=0; $xx<$stream_count; $xx++)
    {
	$sth->execute();     # insert stream_flags record
	if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
	$st_sth->execute();  # get the new st_id (of the new record)
	if ($dbh->err()) { die "$q_name 4\n$st_sql\n$DBI::errstr\n"; }
	($st_id) = $st_sth->fetchrow_array();

	push(@id_array, $st_id);

	sql_ct($dbh, $st_id);
    }
    $sth = $dbh->prepare("update stream_flags set out_stream=? where st_id=?");
    
    # Set all the out streams except the last (which is set below to zero)
    for(my $xx=0; $xx<$#id_array; $xx++)
    {
	$sth->execute($id_array[$xx+1], $id_array[$xx]);
    }
    $sth->execute(0, $id_array[$#id_array]);

    # return the st_id of the first record
    return $id_array[0];
}

sub sql_next_in
{
    my $q_name = "sql_next_in";
    my $dbh = $_[0];

    my $ppid = $$; # getppid();
    my $hostname = `hostname`;
    chomp($hostname);
    print "h:$hostname:$ppid\n";

    my $st_id;
    my $rows = 0;
    my $sth;

    #
    # see mp_init_mysql.pl, st_id of zero must be illegal.
    #
    my $out_stream;
    my $first_done = 0;
    while (! $st_id || ! $out_stream)
    {
	if ($first_done)
	{
	    sleep(1); # sleep after the first try;
	}
	$sth = $dbh->prepare("select st_id from stream_flags where reader_id='none' order by st_id limit 1");
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
	$rows = $sth->execute();
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	($st_id) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("update stream_flags set reader_id='$hostname:$ppid' where st_id=$st_id");
	if ($dbh->err()) { die "doq $q_name 2\n$DBI::errstr\n";  }
	$sth->execute();

	$dbh->commit();
	
	# try to get the st_id we might have just set
	if ($st_id)
	{
	    $sth = $dbh->prepare("select st_id,out_stream from stream_flags where st_id=$st_id and reader_id='$hostname:$ppid'");
	    if ($dbh->err()) { die "doq $q_name 3\n$DBI::errstr\n";  }
	    $rows = $sth->execute();
	    if ($dbh->err()) { die "doq $q_name 4\n$DBI::errstr\n";  }
	    ($st_id, $out_stream) = $sth->fetchrow_array();
	}
	$first_done = 1;
    }

    print "reading $st_id\n";
    return ($st_id, $out_stream);
}

sub sql_read_clean
{
    my $q_name = "sql_read_clean";
    my $dbh = $_[0];
    my $st_id = $_[1];

    my $sql = "drop table stream_row_$st_id";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { 	die "doq $q_name 1\n$DBI::errstr\n";  }
    $sth->execute();
    if ($dbh->err()) { 	die "doq $q_name 2\n$DBI::errstr\n";  }
}


# After the last data has been written to a stream, inactivate it.
# This is "inactive" in the sense that the writer is finished writing.
# The reader may still be reading from this stream.
sub sql_inactivate_stream
{
    my $q_name = "inactivate_stream";
    my $dbh = $_[0];
    my $st_id = $_[1]; # writer inactivates its output stream after last write

    my $sql = "update stream_flags set is_active=0 where st_id=$st_id";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_write_prep
{
    my $q_name = "sql_write_prep";
    my $dbh = $_[0];
    my $st_id= $_[1]; # writer's out_stream

    # prep a statement to insert into that table.
    my $sql = "insert into stream_row_$st_id (st_id_fk,data,marked) values ($st_id,?,0)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    return $sth;
}

sub sql_write
{
    my $q_name = "sql_write";
    my $sth = $_[0];
    my $data = $_[1];

    $sth->bind_param(1,$data, { pg_type => PG_BYTEA });
    if ($sth->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($sth->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

# Move input stream records to read stream with an update.
sub sql_mark
{
    my $q_name = "sql_mark";
    my $dbh = $_[0];
    my $in_stream = $_[1];   # input stream 

    my $sql = "update stream_row_$in_stream set marked=1 where st_id_fk=$in_stream";
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
    my $in_stream = $_[1]; # read stream (intermediate)
    
    #my $sql = "delete from  stream_row_$in_stream where st_id_fk=$in_stream and marked=1";
    my $sql = "delete from  stream_row_$in_stream where marked=1";
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
    my $st_id = $_[1]; # reader's input stream

    my $sql = "select is_active from stream_flags where st_id=$st_id and is_active=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $flag_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    $sql = "select st_id_fk from stream_row_$st_id where st_id_fk=$st_id and marked <> 1 limit 1";
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

sub lock
{
    # see "set transaction"
    # SET TRANSACTION ISOLATION LEVEL { READ COMMITTED | SERIALIZABLE }
    # my $sql = "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE";
    my $q_name = "upd";
    my $dbh = $_[0];

    my $sql = "lock stream_flags"; 
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

1;
