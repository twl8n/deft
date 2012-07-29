use strict;
use DBI;
use DBD::Pg qw(:pg_types);

sub sql_prototype
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sql = "";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_update_bottom
{
    my $q_name = "sql_update_bottom";
    my $dbh = $_[0];
    my $orig_in = $_[1];
    my $in = $_[2];
    my $out = $_[3];
    my $code = $_[4];

    my $sql = "update family set in_stream=$in, out_stream=$out, code=? where in_stream=$orig_in";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($code);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_fid_clean
{
    my $q_name = "sql_fid_clean";
    my $dbh = $_[0];
    my $fid = $_[1];

    my $remaining_stream = 0;

    # see comment below about deleting only marked records.
#     if (! $full_flag)
#     {
# 	# Don't clean up the final stream.
# 	$remaining_stream = pop(@st_id_list);
#     }
    
    my $sth = $dbh->prepare("select out_stream from family where fid=$fid");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    my @sid_list;
    while((my $sid) = $sth->fetchrow_array())
    {
	push(@sid_list, $sid);
    }

    # ... "and marked=1" ?
    my $sth_dr = $dbh->prepare("delete from dbq_row where sr_in=?");
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    my $sth_f = $dbh->prepare("delete from family where out_stream=?");
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }

    foreach my $sid (@sid_list)
    {
	$sth_dr->execute($sid);
	if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }

	$sth_f->execute($sid);
	if ($dbh->err()) { die "$q_name 5\n$DBI::errstr\n"; }
    }
    # return $remaining_stream;
}

sub sql_save_code
{
    my $q_name = "sql_save_code";
    my $dbh = $_[0];
    my $exec = $_[1];

    my $frozen_code = freeze($exec);
    my $sql = "insert into dbq_code (fcode) values (?)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }

    $sth->bind_param(1,$frozen_code, { pg_type => PG_BYTEA });
    if ($sth->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    $sth->execute();
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth = $dbh->prepare("select currval('st_seq')");
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 5\n$DBI::errstr\n"; }
    (my $code_id) = $sth->fetchrow_array();
    return $code_id;
}

sub sql_get_code
{
    my $q_name = "sql_get_code";
    my $dbh = $_[0];
    my $code_id = $_[1];

    my $sql = "select fcode from dbq_code where code_id=$code_id";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $fcode) = $sth->fetchrow_array();
    my $exec = thaw($fcode);
    return $exec;
}


sub sql_cleanse
{
    my $q_name = "sql_cleanse";
    my $dbh = $_[0];
    my $dr_list = $_[1];

    my $sql = "delete from dbq_row where dr_pk in ($dr_list)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

# Assume the writer starts before the reader, so there 
# won't be a case of not finding a stream_flag record.

#my $r_flag = 0;
sub upstream_done
{
    my $q_name = "upstream_done";
    my $dbh = $_[0];
    my $sf_in = $_[1]; # reader's input stream

    #
    # I'm the reader. 
    # Check if any writer is active where the writer's out is my in.
    # Should work if I have multiple writers.
    # 
    my $sql = "select active_flag from family where out_stream=$sf_in";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $af_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    my $flag_rows = 0;
    while((my $af) = $sth->fetchrow_array())
    {
	if ($af == 1)
	{
	    $flag_rows++;
	}
    }

    $sql = "select sr_in from dbq_row where sr_in=$sf_in and marked <> 1 limit 1";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    my $data_rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }

    #write_log("ud> in:$sf_in fr:$flag_rows dr:$data_rows r:$r_flag af:$af_rows");
    #write_log("ud> in:$sf_in fr:$flag_rows dr:$data_rows af:$af_rows");
    
    if ($flag_rows == 0 && $data_rows == 0) # && $r_flag)
    {
 	return 0;
    }
    return 1;
}

my $backdown_count = 0;
sub sql_read
{
    my $q_name = "sql_prototype";
    my $dbh = $_[0];
    my $sr_in = $_[1];

    my $sql = "select dr_pk,data from dbq_row where sr_in=$sr_in";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }

    my $go_flag = 1;
    my $have_record = 0;
    my @records; 
    while (! $have_record && $go_flag)
    {
	#write_log("read loops in:$sr_in");
	my $rows = $sth->execute();
	if ($rows > 0)
	{
	    my $dr_list;
	    my $tween = "";
	    while ((my $dr_pk, my $data) = $sth->fetchrow_array())
	    {
		#write_log("read has data in:$sr_in");
		push(@records, $data);
		$dr_list .= "$tween$dr_pk";
		$tween = ",";
	    }
	    # delete marked records in dbq_row
	    $have_record = 1;
	    #$r_flag = 1; # debug, must read at least one record

	    sql_cleanse($dbh, $dr_list);
	    #sql_update_stream($dbh, $sr_in);
	}
	else
	{
	    # select active_flag from family, select unmarked from dbq_row
	    $go_flag = upstream_done($dbh, $sr_in);
	}
	if ((! $have_record && $go_flag) || ($backdown_count % 5) == 1)
	{
	    my $bd_secs = 1;
	    # my $bd_secs = $backdown_count/5;
	    # write_log("back:$backdown_count in:$sr_in");
	    # Flushing our output before sleeping is an interesting.
	    # It doesn't have much effect.
	    # flush_rewind();
	    sleep($bd_secs);
	}
	$backdown_count++;
    }
    $dbh->commit();
    return @records;
}


sub sql_write
{
    my $q_name = "sql_write";
    my $dbh = $_[0];
    my $sr_in = $_[1];
    my $data = $_[2];

    my $sql = "insert into dbq_row (sr_in,data,marked) values ($sr_in,?,0)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->bind_param(1,$data, { pg_type => PG_BYTEA });
    if ($sth->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    $sth->execute();
    if ($sth->err()) { die "$q_name 3\nsql:$sql\n$DBI::errstr\n"; }
}

# Move input stream records to read stream with an update.
sub sql_mark
{
    my $q_name = "sql_mark";
    my $dbh = $_[0];
    my $sr_in = $_[1];   # input stream 

    my $sql = "update dbq_row set marked=1 where sr_in=$sr_in";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    if ($rows > 0)
    {
	# print "marked:$rows\n";
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
    
    my $sql = "delete from  dbq_row where sr_in=$sr_in and marked=1";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
}



1;
