use strict;
use DBI;
use DBD::Pg qw(:pg_types);

sub upstream_done
{
    my $q_name = "upstream_done";
    my $dbh = $_[0];
    my $aid = $_[1]; # reader's input stream

    my $sql = "select active_flag from family where in_stream=$aid and active_flag=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $flag_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    $sql = "select st_id_fk from stream_row where st_id_fk=$aid and marked<>1 limit 1";
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

# Assume the writer starts before the reader, so there 
# won't be a case of not finding a stream_flag record.
# clean up by deleting records we've finished reading.
sub sql_update_stream
{
    my $q_name = "sql_update_stream";
    my $dbh = $_[0];
    my $aid = $_[1]; # read stream (intermediate)
    
    my $sql = "delete from stream_row where st_id_fk=$aid and marked=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
}

# Move input stream records to read stream with an update.
sub sql_mark
{
    my $q_name = "sql_mark";
    my $dbh = $_[0];
    my $aid = $_[1];   # input stream 

    my $sql = "update stream_row set marked=1 where st_id_fk=$aid";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    if ($rows > 0)
    {
	return 1;
    }
    return 0;
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


sub sql_unwind
{
    my $q_name = "sql_unwind";
    my $dbh = $_[0];
    my $sth = $_[1];
    my $aid = $_[2];

    my $go_flag = 1;
    my $have_record = 0;
    while (! $have_record && $go_flag)
    {
	#
	# If active query handle, then fetch marked records.
	# $sth->Active() seems work, but the docs are vague.
	# The docs say that $sth->rows() may be "unreliable", and may return
	# -1 if the number is not known. We only care if there are rows
	# available, and it seems to work fine with Postgres.
	# The following line works:
	# if (($sth->rows() > 0) && ((my $data) = $sth->fetchrow_array()))
	#

	if (($sth->{Active}) && ((my $data) = $sth->fetchrow_array()))
	{
	    set_ref_eenv(thaw($data));
	    $have_record = 1;
	}
	else
	{
	    # delete marked records
	    sql_update_stream($dbh, $aid);
	    if (sql_mark($dbh, $aid))
	    {
		$dbh->commit();
		# select marked records
		$go_flag = sql_read_execute($sth);
	    }
	    else
	    {
		# is the stream inactive, are there any unmarked records
		$go_flag = upstream_done($dbh, $aid);
	    }
	}
    }
    if (! $have_record)
    {
	clear_eenv();
    }
    return $go_flag;
}

# my $prep_flag = 1;
# Used by the tcp streams version.
sub sql_rewind
{
    my $q_name = "sql_rewind";
    my $dbh = $_[0];
    my $aid = $_[1];

    my $sql = "insert into stream_row (marked,st_id_fk,data) values (0,$aid,?)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $data = freeze_eenv();
    $sth->bind_param(1,$data, { pg_type => PG_BYTEA });
    if ($sth->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    $sth->execute();
    if ($sth->err()) { die "$q_name 3\n$DBI::errstr\n"; }
}

1;

