use strict;
use DBI;
# use DBD::Pg qw(:pg_types);

sub sql_proto_a
{
    my $q_name = "sql_proto_a";
    my $dbh = $_[0];
    my $sql = "";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

#
# Means rewinding is done.
# Might be used by dbq and tcp versions. Not used by st version.
# When there are multiple writers to a stream, not all writers
# will finish simultaneously, so each writer (distinguished by its
# input stream) needs to separately inactivate.
# 

sub sql_inactivate_ancestor
{
    my $q_name = "sql_inactivate_ancestor";
    my $dbh = $_[0];
    my $in_s = $_[1]; # writer's input stream
    my $out_s = $_[2]; # writer's output stream

    my $sql = "update family set active_flag=0 where in_stream=$in_s and out_stream=$out_s";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    my $rows = $sth->execute();
    if ($dbh->err()) { die "$q_name 2\nsql:$sql\n$DBI::errstr\n"; }
    $sth->finish();

    #write_log("inactivates: rows:$rows in:$in_s out:$out_s");
}


sub sql_new_stream_id
{
    my $q_name = "sql_new_stream_id";
    my $dbh = $_[0];

    my $sql = "select nextval('st_seq')";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $st_id) = $sth->fetchrow_array();
    return $st_id;
}

sub sql_get_ancestor
{
    my $q_name = "sql_get_ancestor";
    my $dbh = $_[0];
    my $aid = $_[1];

    my $sql = "select out_stream,code,fid from family where in_stream=$aid";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    (my $nok, my $code, my $fid) = $sth->fetchrow_array();
    $sth->finish();
    return ($nok, $code, $fid);
}

sub sql_new_ancestor
{
    my $q_name = "sql_new_ancestor";
    my $dbh = $_[0];
    my $nok = $_[1]; # out
    my $aid = $_[2]; # in 
    my $code = $_[3];
    my $fid = $_[4];

    if ($fid == 0)
    {
	$fid = sql_new_stream_id($dbh);
    }

    my $sql = "insert into family (fid, out_stream, in_stream, code) values ($fid, $nok, $aid, ?)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($code);
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    $sth->finish();
    return $fid;
}

sub sql_update_config
{
    my $q_name = "sql_update_config";
    my $dbh = $_[0];
    my $name = $_[1];
    my @values = @{$_[2]};

    my $sth = $dbh->prepare("delete from config where name='$name'");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    $sth = $dbh->prepare("insert into config (name,value) values ('$name',?)");
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    foreach my $value (@values)
    {
	$sth->execute($value);
	if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    }
}

sub sql_next_host
{
    my $q_name = "sql_next_hots";
    my $dbh = $_[0];
    my $prev_host = $_[1];

    my $sth = $dbh->prepare("select value from config 
				where name='active_hosts' and value<>'$prev_host' 
				order by value limit 1");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $host) = $sth->fetchrow_array();
    if (! $host)
    {
	$host = $prev_host;
    }
    return $host;
}


sub sql_config
{
    my $q_name = "sql_config";
    my $dbh = $_[0];
    my $name = $_[1];
    my $sql = "select value from config where name='$name' order by value";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    my @result;
    while((my $value) = $sth->fetchrow_array())
    {
	push(@result, $value);
    }
    return @result;
}

sub sql_update_hosts
{
    my $q_name = "sql_update_hosts";
    my $dbh = $_[0];
    my @active_hosts = @{$_[1]};

    my $sth = $dbh->prepare("delete from config where name='active_hosts'");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    $sth = $dbh->prepare("insert into config (name,value) values ('active_hosts',?)");
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    foreach my $host (@active_hosts)
    {
	print "active $host\n";
	$sth->execute($host);
	if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    }
}


sub sql_currval
{
    my $q_name = "sql_currval";
    my $dbh = $_[0];
    my $seq = $_[1];
    my $sql = "select currval(\'$seq\');";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    my $pk = $sth->fetchrow_array();
    return $pk;
}

sub sql_clear_graph
{
    my $q_name = "sql_clear_";
    my $dbh = $_[0];
    my $gr_pk = $_[1];

    # edges
    my $sql = "delete from edge where gr_fk=$gr_pk";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    # nodes
    $sql = "delete from node where gr_fk=$gr_pk";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    # code
    $sql = "delete from code where gr_fk=$gr_pk";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    # graph
    $sql = "delete from graph where gr_pk=$gr_pk";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_node_ok
{
    my $q_name = "sql_node_ok";
    my $dbh = $_[0];
    my $gr_pk = $_[1];
    my $node_pk = $_[2];

    my $sql = "select ec_pk from edge where gr_fk=? and from_node_fk=?";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($gr_pk, $node_pk);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    if ($sth->rows() > 0)
    {
	return 1;
    }
    return 0;
}

sub sql_code_exists
{
    my $q_name = "sql_code_exists";
    my $dbh = $_[0];
    my $code_name = $_[1];
    my $file_date = $_[2];
    my $gr_pk = $_[3];
    
    #
    # Use DBI ? to avoid Perl interpolating strings, ticks, etc.
    # 

    my $sql = "select code_pk,(code_date < '$file_date') as reload_flag
		from code where code_name=? and gr_fk=?";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($code_name, $gr_pk);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    #
    # If the record doesn't exist, load it, therefore $reload_flag defaults to 1.
    #
    my $code_pk = 0;
    my $reload_flag = 1;
    if ($sth->rows())
    {
	($code_pk, $reload_flag) = $sth->fetchrow_array();
    }
    return ($code_pk, $reload_flag);
}

sub sql_update_code
{
    my $q_name = "sql_update_code";
    my $dbh = $_[0];
    my $code_pk = $_[1];
    my $source = $_[2];
    my $file_date = $_[3];
    my $gr_pk = $_[4];

    #
    # Use DBI ? to avoid Perl interpolating strings, ticks, etc.
    # 

    if ($code_pk==1)
    {
	# print "suc:$source\n";
    }
    my $sql = "update code set source=?,code_date=? where code_pk=? and gr_fk=$gr_pk";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($source,
		  $file_date,
		  $code_pk);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_insert_code
{
    my $q_name = "sql_insert_code";
    my $dbh = $_[0];
    my $code_name = $_[1];
    my $source = $_[2];
    my $file_date = $_[3];
    my $gr_pk = $_[4];

    #
    # Use DBI ? to avoid Perl interpolating strings, ticks, etc.
    # 
    my $sql = "insert into code (code_name,source,code_date,gr_fk) values (?,?,?,?)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($code_name, $source, $file_date,$gr_pk);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    
    #
    # Get the code_pk for the record we just inserted.
    #
    $sql = "select currval('code_seq')";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    (my $code_pk) = $sth->fetchrow_array();

    #
    # update the edges
    #
    $sql = "update edge set code_fk=$code_pk where code_var_name='$code_name' and gr_fk=$gr_pk and is_var=0";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }


    return $code_pk;
}

sub sql_exists_template
{
    my $q_name = "sql_exists_template";
    my $dbh = $_[0];
    my $te_name = $_[1];

    my $sql = "select te_pk from template where te_name=?";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($te_name);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $te_pk) = $sth->fetchrow_array();
    return $te_pk;
}

sub sql_get_template
{
    my $q_name = "sql_get_template";
    my $dbh = system_dbh();
    my $te_name = $_[0];
    my $te_epoch = $_[1];

    my $sql = "select
	te_pk,
	(te_date < timestamp with time zone '1970-01-01' + $te_epoch * interval '1 second') as rc_flag,
	te_code,
	te_date
 	from template where te_name=?";

    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($te_name);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    if ((my $te_pk, my $rc_flag, my $te_code, my $te_date) = $sth->fetchrow_array())
    {
	return ($te_pk, $rc_flag, $te_code);
    }
    return (0,1,0);
}

# Note 1
# From the DBD::Pg man page
# IMPORTANT: The undocumented (and invalid) support for the "SQL_BINARY"
# data type is officially deprecated. Use "PG_BYTEA" with
# "bind_param()" instead:
# $rv = $sth->bind_param($param_num, $bind_value,
# { pg_type => DBD::Pg::PG_BYTEA });

sub sql_insert_template
{
    my $q_name = "sql_insert_template";
    my $dbh = system_dbh();
    my $te_name = $_[0];
    my $te_code = $_[1]; # a frozen hash, now binary data.
    my $te_epoch = $_[2];

    # New code for sqlite, which has no dates and might be less picky
    # about binary data going into a text field.

    if (1)
    {
	my $sql = "insert into template (te_name,te_code,te_date) values (?,?,?)";

	my $sth = $dbh->prepare($sql);
	if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }

	$sth->execute($te_name, $te_code, $te_epoch);
	if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    }
    else
    {
	my $sql = "insert into template (te_name,te_code,te_date)
		values
		(?,?,timestamp with time zone '1970-01-01' + $te_epoch * interval '1 second')";
	
	my $sth = $dbh->prepare($sql);
	if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
	
	# See note 1 above.
	
	$sth->bind_param(1,$te_name);
	$sth->bind_param(2,$te_code, { pg_type => DBD::Pg::PG_BYTEA });
	$sth->execute();
	
	if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    }

    # if (0)
    # {
    # 	$sql = "select currval('pk_seq')";
    # 	$sth = $dbh->prepare($sql);
    # 	if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    # 	$sth->execute();
    # 	if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    # 	(my $te_pk) = $sth->fetchrow_array();
    # }

    my $te_pk = sql_currval();
    $dbh->commit();
    return $te_pk;
}

sub sql_update_template
{
    my $q_name = "sql_update_template";
    my $dbh = system_dbh();
    my $te_code = $_[0]; # frozen, so now it is binary data.
    my $te_epoch = $_[1];
    my $te_pk = $_[2];
    
    my $sql = "update template set te_code=?,
		te_date=timestamp with time zone '1970-01-01' + $te_epoch * interval '1 second'
		where te_pk=$te_pk";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    
    # See note 1 above.

    # $sth->bind_param(1,$te_code, { pg_type => DBD::Pg::PG_BYTEA });
    $sth->bind_param(1,$te_code);
    $sth->execute();
    
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }
    $dbh->commit();
}



#
# This could just return 1, which will always be the
# starting node_pk however, we check the edge table
# as a sanity check.
# 
sub sql_initial_node_pk
{
    my $q_name = "sql_initial_node_pk";
    my $dbh = $_[0];
    my $gr_fk = $_[1];

    my $sql = "select min(from_node_fk) from edge where gr_fk=$gr_fk";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $node_pk) = $sth->fetchrow_array();
    return $node_pk;
}

sub sql_clean_graph
{
    my $q_name = "sql_clean_graph";
    my $dbh = $_[0];
    my $gr_fk = $_[1];
    my $file_date = $_[2];

    # There are no nodes, and the node table is empty.
    # my $sql = "delete from edge where from_node_fk in (select node_pk from node where gr_fk=$gr_fk)";
    # my $sth = $dbh->prepare($sql);
    # if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    # $sth->execute();
    # if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    # Everything is an edge, leading from one edge to another.
    my $sql = "delete from edge where gr_fk=$gr_fk\n";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }

    $sql = "update graph set gr_date='$file_date' where gr_pk=$gr_fk";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 5\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 6\n$DBI::errstr\n"; }
    
}

#
# Called from load_graph.pl(?)
# Checks the given $file_date and returns a flag true 
# if the database record is older and needs a reload.
#
sub sql_graph_info_by_name
{
    my $q_name = "sql_graph_info_by_name";
    my $dbh = $_[0];
    my $gr_path = $_[1];
    my $graph_name = $_[2];
    my $file_date = $_[3];
    my $logname = $_[4];

    my $gr_pk;
    my $gr_date;
    my $reload_flag;

    my $sql = "select gr_pk,gr_date,(gr_date < '$file_date') as reload_flag
		from graph where gr_path=? and graph_name=? and du_fk=(select du_pk from deft_users where logname=?)";

    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($gr_path, $graph_name,$logname);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    if ($sth->rows() == 1)
    {
	#
	# Perl DBI translates SQL boolean t and f to 1 and zero.
	#
	($gr_pk, $gr_date, $reload_flag) =  $sth->fetchrow_array();
    }
    #
    # If the gr_date is zero, null, or undef
    # we want to reload.
    #
    if (! $gr_date)
    {
	$reload_flag = 1;
    }
    return ($gr_pk,$gr_date,$reload_flag);
}

#
# Called from machine.pl
# Just a simple sub to get the gr_pk.
# Also returns the gr_path.
#
sub sql_gr_pk
{
    my $q_name = "sql_gr_pk";
    my $dbh = $_[0];
    my $graph_name = $_[1];
    my $logname = $_[2];

    my $sql = "select gr_pk,gr_path from graph where graph_name=? and
		du_fk=(select du_pk from deft_users where logname=?)";

    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($graph_name, $logname);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    my $gr_pk = 0;
    my $gr_path = "";
    if ($sth->rows() == 1)
    {
	($gr_pk, $gr_path) =  $sth->fetchrow_array();
    }
    return ($gr_pk, $gr_path);
}

sub sql_insert_graph
{
    my $q_name = "sql_insert_graph";
    my $dbh = $_[0];
    my $gr_path = $_[1];
    my $graph_name = $_[2];
    my $file_date = $_[3];
    my $logname = $_[4];


    (my $gr_pk,
     my $gr_date,
     my $reload_flag) = sql_graph_info_by_name($dbh,
					       $gr_path,
					       $graph_name,
					       $file_date,
					       $logname);
    if (! $reload_flag)
    {
	return ($gr_pk,$reload_flag);
    }

    if ($gr_pk)
    {
	sql_clean_graph($dbh, $gr_pk, $file_date);
    }
    else
    {
	my $sql = "insert into graph (gr_path, graph_name,gr_date,du_fk)
		values (?,?,?,(select du_pk from deft_users where logname=?))";
	my $sth = $dbh->prepare($sql);
	if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
	$sth->execute($gr_path, $graph_name, $file_date, $logname);
	if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
	
	$sql = "select currval('graph_seq')";
	$sth = $dbh->prepare($sql);
	if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
	$sth->execute();
	if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
	($gr_pk) = $sth->fetchrow_array();
    }
    return ($gr_pk,$reload_flag);
}

sub sql_insert_node
{
    my $q_name = "sql_insert_node";
    my $dbh = $_[0];
    my $gr_fk = $_[1];
    my $node_name = $_[2];
    my $sql = "insert into node (gr_fk,node_name) values ($gr_fk,'$node_name')";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }

    $sql = "select currval('node_seq')";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    (my $node_pk) = $sth->fetchrow_array();
    return $node_pk;
}

sub sql_insert_edge_var
{
    my $q_name = "sql_insert_edge_var";
    my $dbh = $_[0];
    my $code_var_name = $_[1];
    my $edge_order = $_[2];
    my $from_node_fk = $_[3];
    my $to_node_fk = $_[4];
    my $invert = $_[5];
    my $is_wait = $_[6];
    my $gr_pk = $_[7];


    my $sql = "insert into edge
	( edge_order, from_node_fk, to_node_fk,  code_var_name,  invert, is_wait,is_var, gr_fk) values
	($edge_order,$from_node_fk,$to_node_fk,'$code_var_name',$invert,$is_wait,1,     $gr_pk)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
}

sub sql_insert_edge
{
    my $q_name = "sql_insert_edge";
    my $dbh = $_[0];
    my $code_name = $_[1];
    my $edge_order = $_[2];
    my $from_node_fk = $_[3];
    my $to_node_fk = $_[4];
    my $invert = $_[5];
    my $is_wait = $_[6];
    my $gr_pk = $_[7];

    #
    # First get the code_pk, then insert the new edge.
    # 
    my $sql = "select code_pk from code where code_name=? and gr_fk=?";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute($code_name, $gr_pk);
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    my $code_pk;
    if ($sth->rows() == 0)
    {
	print "No rows returned for edge named:$code_name for gr_pk:$gr_pk\n";
	#$sth->finish();
	#$dbh->disconnect();
	#exit();
	$code_pk = 0;
    }
    else
    {
	($code_pk) = $sth->fetchrow_array();
    }

    $sql = "insert into edge
	( edge_order, code_fk, from_node_fk, to_node_fk, invert, is_wait, gr_fk,  code_var_name) values
	($edge_order,$code_pk,$from_node_fk,$to_node_fk,$invert,$is_wait,$gr_pk,'$code_name')";
    $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 4 $sql\n$DBI::errstr\n"; }
}

sub sql_load_node
{
    my $q_name = "sql_load_node";
    my $dbh = $_[0];
    my $node_pk = $_[1];

    my $sql = "select code_name,source from code,node where code_fk=code_pk and node_pk=$node_pk";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    (my $code_name,my $source) = $sth->fetchrow_array();
    $sth->finish();
    return ($code_name, $source);
}

sub sql_load_edges
{
    my $q_name = "sql_load_edges";
    my $dbh = $_[0];
    my $gr_pk = $_[1];
    my $node_pk = $_[2];
    
    #
    # Prep and execute a statement to get the edges.
    # Must be in ascending order by edge_order.
    # Get all the fields.
    # 
    my $sql = "select * from edge where from_node_fk=$node_pk and gr_fk=$gr_pk order by edge_order";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    $sth->execute();
    if ($dbh->err()) { die "$q_name 2\n$sql\n$DBI::errstr\n"; }

    #
    # Prepare a statement for getting source, if we need it.
    # Edges that are is_var don't have any source.
    #
    my $code_sql = "select code_name,source from code where code_pk=?";
    my $code_sth = $dbh->prepare($code_sql);
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }

    my @e_array;
    while(my $hr = $sth->fetchrow_hashref())
    {
	if (! $hr->{is_var})
	{
	    $code_sth->execute($hr->{code_fk});
	    if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
	    ($hr->{code_name}, $hr->{source}) = $code_sth->fetchrow_array();
	    
	}
	push(@e_array, $hr);
    }
    return @e_array;
}

sub sql_duo_clean
{
    my $q_name = "sql_duo_clean";
    my $dbh = $_[0];
    my @st_id_list = @{$_[1]};
    my $full_flag = $_[2];
    my $remaining_stream = 0;

    if (! $full_flag)
    {
	# Don't clean up the final stream.
	$remaining_stream = pop(@st_id_list);
    }
    
    my $sth = $dbh->prepare("delete from dbq_row where sr_in=?");
    if ($dbh->err()) { die "$q_name 1\n$DBI::errstr\n"; }
    foreach my $out_stream_fk (@st_id_list)
    {
	$sth->execute($out_stream_fk);
	if ($dbh->err()) { die "$q_name 2\n$DBI::errstr\n"; }
    }

    $sth = $dbh->prepare("delete from family where out_stream=?");
    if ($dbh->err()) { die "$q_name 3\n$DBI::errstr\n"; }
    foreach my $st_id (@st_id_list)
    {
	$sth->execute($st_id);
	if ($dbh->err()) { die "$q_name 4\n$DBI::errstr\n"; }
    }
    $sth->finish();
    return $remaining_stream;
}


1;
