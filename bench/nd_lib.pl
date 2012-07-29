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

    $dbh->do("delete from stream_flags");
}

sub sql_read
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sth = $_[1];
    my $in_stream = $_[2];

    my $nd_fk = 0;
    my $commit_flag = 0;
    my $go_flag = 1;
    my $have_record = 0;
    my $data = undef;
    while (! $have_record && $go_flag)
    {
        if (($sth->{Active}) && (($data) = $sth->fetchrow_array()))
        {
            $have_record = 1;
        }
        else
        {
            # delete marked records
            #sql_update_stream($dbh, $in_stream);
            if ($nd_fk = sql_mark($dbh, $in_stream))
            {
		print "reading nd_fk:$nd_fk\n";
                # select marked records
                $go_flag = sql_read_execute($sth, $nd_fk);
		$commit_flag = 1;
            }

            if (! $go_flag || ! $nd_fk) # if ($nd_fk) # no nd_fk means we continue
            {
                # is the stream inactive, are there any unmarked records
                $go_flag = upstream_done($dbh, $in_stream);
		# print "g:$go_flag i:$in_stream\n";
            }
        }
    }
    return ($data, $commit_flag);
}

sub sql_read_prep
{
    my $q_name = "sql_read_prep";
    my $dbh = $_[0];
    my $st_id = $_[1]; # reader's read_stream

    # nd_fk is unique, so this is the only condition we need.
    my $sql = "select data from stream_row where nd_fk=?";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    return $sth; 
}

# Read records from the intermediate read stream.
# Check upstream to see if we should continue.
sub sql_read_execute
{
    my $q_name = "sql_read_execute";
    my $sth = $_[0];
    my $nd_fk = $_[1];

    my $rows = $sth->execute($nd_fk); 
    if ($sth->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    if ($rows > 0)
    {
	print "sel for read:$rows\n";
	return 1;
    }
    else
    {
	return 0;
    }
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
    
    my $st_sql = "select max(st_id) from stream_flags"; # currval('st_seq')";
    my $st_sth = $dbh->prepare($st_sql);
    if ($dbh->err()) { die "$q_name 2\n$st_sql\n$DBI::errstr\n"; }

    my $st_id;
    my @id_array;
    for(my $xx=0; $xx<$stream_count; $xx++)
    {
	$sth->execute();     # insert stream_flags record
	if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
	$st_sth->execute();  # get the new st_id (of the new record)
	if ($dbh->err()) { die "$q_name 4\n$st_sql\n$DBI::errstr\n"; }
	($st_id) = $st_sth->fetchrow_array();

	push(@id_array, $st_id);
    }
    $sth = $dbh->prepare("update stream_flags set out_stream=? where st_id=?");
    if ($dbh->err()) { die "$q_name 5\n$st_sql\n$DBI::errstr\n"; }
    
    # Set all the out streams except the last (which is set below to zero)
    for(my $xx=0; $xx<$#id_array; $xx++)
    {
	$sth->execute($id_array[$xx+1], $id_array[$xx]);
	if ($dbh->err()) { die "$q_name 5\n$st_sql\n$DBI::errstr\n"; }
    }
    $sth->execute(0, $id_array[$#id_array]);
    if ($dbh->err()) { die "$q_name 6\n$st_sql\n$DBI::errstr\n"; }

    # return the st_id of the first record
    return $id_array[0];
}

# sql_next_in returns both in and out
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
    # see sr_init.pl, st_id of zero must be illegal.
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
	$rows = $sth->execute();
	if ($dbh->err()) { die "doq $q_name 1\n$DBI::errstr\n";  }
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
    my $st_id= $_[1]; # writer's id, not an output stream per se.

    # insert nd_keys
    my $sth = $dbh->prepare("insert into nd_keys (st_id_fk) values ($st_id)");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    # select new, current nd_pk
    $sth = $dbh->prepare("select currval('st_seq')");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $nd_fk) = $sth->fetchrow_array();


    #
    # Prepare a statement we'll execute many times in sql_write(); 
    #
    print "writing nd_fk:$nd_fk\n";
    $sth = $dbh->prepare("insert into stream_row (st_id_fk,data,nd_fk) values ($st_id,?,$nd_fk)");
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
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

    my $sth = $dbh->prepare("select nd_pk from nd_keys where st_id_fk=$in_stream limit 1");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $nd_pk) = $sth->fetchrow_array();
    sql_delete_nd_key($dbh, $nd_pk);

    return $nd_pk;
}

sub sql_delete_nd_key
{
    my $q_name = "sql_delete_nd_key";
    my $dbh = $_[0];
    my $nstr = $_[1];

    my $sth = $dbh->prepare("delete from nd_keys where nd_pk=?");
    if ($dbh->err()) { 	die "doq $q_name 1\n$DBI::errstr\n";  }
    $sth->execute($nstr);
    if ($dbh->err()) { 	die "doq $q_name 2\n$DBI::errstr\n";  }
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
    #my $nd_fk = $_[2]; # reader's nd key

    my $sql = "select is_active from stream_flags where st_id=$st_id and is_active=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $flag_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    $sql = "select st_id_fk from nd_keys where st_id_fk=$st_id limit 1";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    my $data_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    
    #print "st_id:$st_id dr:$data_rows\n";
    
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
