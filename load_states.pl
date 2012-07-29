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
    if ($#ARGV < 0)
    {
	print "Usage: ./load_states.pl graph_name\n";
	print "States are related to the named graph,\n";
	print "and must be in the same directory as the graph file.\n";
	exit(1);
    }
    my $dbh = deft_db_connect();

    my $logname = `/usr/bin/id -nu`;
    chomp($logname);

    my $graph_name = shift(@ARGV);

    (my $gr_pk, my $gr_path) = sql_gr_pk($dbh, $graph_name, $logname);
    if (! $gr_pk)
    {
	print "No gr_pk for graph:$graph_name and logname:$logname\n";
	$dbh->disconnect();
	exit();
    }
    my $temp = chdir($gr_path);
    if ($temp != 1)
    {
	print "Error: apparently cannot chdir to $gr_path\n";
	$dbh->disconnect();
	exit();
    }
    my @file_list = `/usr/bin/find ./ -maxdepth 1 -name '*.deft'`;
    chomp(@file_list);
    foreach my $file (@file_list)
    {
	my $stem = $file;
	$stem =~ s/.*\///;       # stip path
	$stem =~ s/(.*)\..*/$1/; # file stem before dot
	$stem = lc($stem);
	
	# (my $source, my $file_date) = read_file($file, 1);
	(my $source, my $file_date) = read_deft($file);
	
	state_code_to_db($dbh, $stem, $source, $file_date, $gr_pk);       # deftlib.pl
    }
    $dbh->commit();
    $dbh->disconnect();
}

# called from load_states.pl
sub state_code_to_db
{
    my $dbh = $_[0];
    my $code_name = $_[1];
    my $source = $_[2];
    my $file_date = $_[3];
    my $gr_pk = $_[4];

    #
    # If the code doesn't exist, code_pk will probably come back undef
    #
    (my $code_pk, my $reload_flag) = sql_code_exists($dbh, $code_name, $file_date, $gr_pk);
    if (! $reload_flag)
    {
	print "File is older than db. $code_name not reloaded.\n";
	return;
    }
    else
    {
	if ($code_pk)
	{
	    sql_update_code($dbh, $code_pk, $source, $file_date, $gr_pk);
	}
	else
	{
	    sql_insert_code($dbh, $code_name, $source, $file_date, $gr_pk);
	}
	print "Loaded $code_name.\n";
    }
}
