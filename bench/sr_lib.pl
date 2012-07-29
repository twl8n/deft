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
    my $sth = $_[1];
    my $in_stream = $_[2];

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
            # delete marked records in stream_row
            sql_update_stream($dbh, $in_stream);
            if (sql_mark($dbh, $in_stream))
            {
                $dbh->commit();
                # select marked records from stream_row
                $go_flag = sql_read_execute($sth);
            }
            else
            {
                # select is_active from stream_flags, select unmarked from stream_row
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

    my $sql = "select data from stream_row where st_id_fk=$st_id and marked=1";
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
# Init a family of streams, all active, none have readers yet.
sub sql_init_streams
{
    my $q_name = "sql_init_streams";
    my $dbh = $_[0];
    my @id_list = @{$_[1]}; # writer inits, writer writes to st_id

    my $sql = "insert into stream_flags (st_id, is_active, reader_id) values (?,1,'none')";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    foreach my $st_id (@id_list)
    {
	# $dbh->do("insert into stream_flags (st_id, is_active, reader_id) values ($st_id,1,'none')");
	$sth->execute($st_id);
	if ($dbh->err()) { die "$q_name 2 s:$st_id sql:$sql\n$DBI::errstr\n"; }
    }
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

    #
    # see sr_init.pl, st_id of zero must be illegal.
    #
    while (! $st_id)
    {
	my $sql = "lock stream_flags"; 
	my $sth = $dbh->prepare($sql);
	if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
	$sth->execute();
	if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

	$sth = $dbh->prepare("select st_id from stream_flags where reader_id='none' order by st_id limit 1");
	$rows = $sth->execute();
	if ($dbh->err()) {  die "doq $q_name 1\n$DBI::errstr\n";  }
	($st_id) = $sth->fetchrow_array();
	$sth->finish();

	$sth = $dbh->prepare("update stream_flags set reader_id='$hostname:$ppid' where st_id=$st_id");
	if ($dbh->err()) {  die "doq $q_name 2\n$DBI::errstr\n";  }
	$sth->execute();

	$dbh->commit(); # unlock
    }

    if (1)
    {
	my $sql = "select * from stream_flags where reader_id='$hostname:$ppid'";
	my $sth = $dbh->prepare($sql);
	if ($dbh->err()) { 	die "doq $q_name 1\n$DBI::errstr\n";  }
	$sth->execute();
	if ($dbh->err()) { 	die "doq $q_name 2\n$DBI::errstr\n";  }
	while(my $hr = $sth->fetchrow_hashref())
	{
	    foreach my $item (keys(%{$hr}))
	    {
		print "s:$item $hr->{$item}\n";
	    }
	}
    }
    print "reading $st_id\n";
    return $st_id;
}

# Streams are created active, and I can't see a reason to
# have a separate activation step.
# sub sql_activate_stream
# {
#     my $q_name = "activate_stream";
#     my $dbh = $_[0];
#     my $st_id = $_[1]; # writer activates its output stream after first write.

#     my $sql = "update stream_flags set is_active=1 where st_id=$st_id";
#     my $sth = $dbh->prepare($sql);
#     if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
#     $sth->execute();
#     if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
# }

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

    # streams are all set to active in sql_init_streams
    my $sql = "insert into stream_row (st_id_fk,data,marked) values ($st_id,?,0)";
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

    my $sql = "update stream_row set marked=1 where st_id_fk=$in_stream";
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
    
    my $sql = "delete from  stream_row where st_id_fk=$in_stream and marked=1";
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
    
    $sql = "select st_id_fk from stream_row where st_id_fk=$st_id and marked <> 1 limit 1";
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
    my $q_name = "upd";
    my $dbh = $_[0];
    # my $sql = "lock stream_row  in row exclusive mode";
    my $sql = "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

1;
