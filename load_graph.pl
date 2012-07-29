#!/opt/local/bin/perl
use strict;
use Cwd qw(abs_path);

sub robust_path
{
    my $rpath = $_[0];
    if (! $rpath)
    {
	$rpath = "./";
    }
    my $new_rpath = abs_path($rpath);
    if ($new_rpath)
    {
	$rpath = $new_rpath;
    }
    # else abs_path() couldn't get the absolute path. Symlinks?
    $rpath =~ /^([-\/\@\w.]+)$/; # untaint
    $rpath = $1;
    return $rpath;
}

my $path;
if ($0 =~ m/(.*)\//)
{
    $path = robust_path($1);
}
else
{
    $path = robust_path("./");
}

require "$path/sql_lib.pl";
require "$path/common_lib.pl";
require "$path/st_lib.pl";

main:
{
    if ($#ARGV != 0)
    {
	print "usage: load_graph.pl graph_file_name\n";
	print "Graph is owned by who you're logged in as.\n";
	exit();
    }
    my $gr_file_name = $ARGV[0];
    #
    # Make sure the file name has a path component.
    # 
    if ($gr_file_name !~ m/\//)
    {
	$gr_file_name = ".\/$gr_file_name";
    }
    (my $all, my $file_date) = read_file("$gr_file_name", 1);

    my $logname = `/usr/bin/id -nu`;
    chomp($logname);

    my $dbh = deft_db_connect();

    # Pull off the first line of the graph withe graph name.
    $all =~ s/(.*)//m;
    my $graph_name = $1;

    # Send the path component of $gr_file_name to robust_path().
    $gr_file_name =~ m/(.*)\//;
    my $gr_path = robust_path($1); # deftlib.pl

    print "Graph name:$graph_name\n";
    my $gr_pk = 0;
    my $reload_flag = 0;
    if (-f "$gr_file_name")
    {
	($gr_pk, $reload_flag) = sql_insert_graph($dbh, $gr_path, $graph_name, $file_date, $logname);
    }
    else
    {
	print "Error file not found: $gr_file_name.\n";
	$dbh->disconnect();
	exit();
    }
    if (! $gr_pk)
    {
	print "Error: No graph found with name \"$graph_name\" (file \"$gr_file_name\").\n";
	$dbh->disconnect();
	exit();
    }

    if (! $reload_flag)
    {
	print "File is older. Not reloaded.\n";
	$dbh->disconnect();
	exit();
    }
    
    sql_clean_graph($dbh, $gr_pk, $file_date);

    (my $first_node_pk) = string2db($dbh, $gr_pk, $all);

    print "Graph pk (gr_pk):$gr_pk\n";
    print "First node_pk:$first_node_pk\n";
    $dbh->commit();
    $dbh->disconnect();
}

sub string2db
{
    my $dbh = $_[0];
    my $gr_pk = $_[1];
    my $all = $_[2];
    my %nodes; 
    my $first_node_pk;

    #
    # Remove comments;
    # 

    $all =~ s/#.*$//mg;
    my $node_pk = 0;
    while($all =~ m/(.+?)\s+(.+?)\s+(.*)/g)
    {
	my $wait_flag = 0;
	my $start = $1;
	my $edge = $2;
	my $finish = $3;
	if ($finish =~ s/wait,(.*)/$1/)
	{
	    $wait_flag = 1;
	}


	if (! exists($nodes{$start}))
	{
	    # my $node_pk = sql_insert_node($dbh, $gr_pk, $start);
	    $node_pk++;
	    $nodes{$start}[0] = 0;
	    $nodes{$start}[1] = $node_pk;
	}
	if (! exists($nodes{$finish}))
	{
	    #my $node_pk = sql_insert_node($dbh, $gr_pk, $finish);
	    $node_pk++;
	    $nodes{$finish}[0]++;
	    $nodes{$finish}[1] = $node_pk;
	}
	#
	# If the edge name has a leading !, then set invert to true.
	# Remove the !
	#
	my $invert = 0;
	if ($edge =~ s/^\!//)
	{
	    $invert = 1;
	}
	#
	# If the edge is a double quoted string, then it must be
	# a named variable instead of name of deft script.
	# Remove the "".
	#
	if ($edge =~ s/^\"(.*)\"$/$1/ || $edge eq 'true' or $edge eq 'false')
	{
	    sql_insert_edge_var($dbh,
				$edge,               # var_name
				$nodes{$start}[0],   # edge_order
				$nodes{$start}[1],   # from_node_fk
				$nodes{$finish}[1],  # to_node_fk
				$invert,             # invert logic of return value
				$wait_flag,          # wait before transition to node
				$gr_pk);
	}
	else
	{
	    sql_insert_edge($dbh,
			    $edge,               # code_name
			    $nodes{$start}[0],   # edge_order
			    $nodes{$start}[1],   # from_node_fk
			    $nodes{$finish}[1],  # to_node_fk
			    $invert,             # invert logic of return value
			    $wait_flag,          # wait before transition to node
			    $gr_pk);             # graph containting this edge
	}

	$nodes{$start}[0]++;
	if (! $first_node_pk)
	{
	    $first_node_pk = $nodes{$start}[1];
	}
	print "s:$start($nodes{$start}[1]) e:$edge f:$finish ($nodes{$finish}[1])\n";
    }
    return $first_node_pk;
}
