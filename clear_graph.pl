#!/opt/local/bin/perl
use strict;
$0 =~ m/(.*)\//;
my $path = $1;

require "$path/deftlib.pl";
main:
{
    if ($#ARGV != 0)
    {
	print "usage: clear_graph.pl graph_file_name\n";
	print "Graph is owned by who you're logged in as.\n";
	exit();
    }

    my $logname = `/usr/bin/id -nu`;
    chomp($logname);

    my $dbh = deft_db_connect();
    #
    # This would almost be simpler with two hashes
    # key is node name, [0] is edge_count, [1] is node_pk
    #
    my $graph_name = $ARGV[0];
    print "Graph name:$graph_name\n";
    
    (my $gr_pk) = sql_gr_pk($dbh, $graph_name, $logname);
    if ($gr_pk)
    {
	sql_clear_graph($dbh, $gr_pk);
	print "Cleared $graph_name\n";
	$dbh->commit();
    }
    else
    {
	print "Graph $graph_name not found for user:$logname\n";
    }
    $dbh->disconnect();
}

