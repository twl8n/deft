#!/opt/local/bin/perl

# This is part of Deft and the DeFindIt Classic Search engine.

#Copyright (C) 2003,2004 Tom Laudeman, Noah Healy.

#This library is free software; you can redistribute it and/or
#modify it under the terms of the GNU Lesser General Public
#License as published by the Free Software Foundation; either
#version 2.1 of the License, or (at your option) any later version.
#
#This library is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#Lesser General Public License for more details.
#
#You should have received a copy of the GNU Lesser General Public
#License along with this library; if not, write to the Free Software
#Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

use strict;
use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
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
require "$path/runt_compile.pl";


sub machine_exit
{
    my $dbh = $_[0];
    $dbh->disconnect();
    clean_db_handles();
    exit(0);
}

sub machine_error
{
    my $dbh = $_[0];
    my $message = $_[1];
    $dbh->disconnect();

    write_log("There was an error: $message\n");
    clean_db_handles();
    exit(0);
}

sub test_vars
{
    my $var_name = $_[0];
    my $result;

    if ($var_name eq 'true')
    {
	$result = 1;
    }
    elsif ($var_name eq 'false')
    {
	$result = 0;
    }
    else
    {
	#
	# 2004-10-21
	# Why the heck is deft_cgi() being called here?
	# It (used to) rewinds, so this looks like a really bad idea.
	# I commented it out.
	# 2004-10-23
	# It is called to retrieve the CGI and shove it into
	# eenv. It no longer rewinds.
	# 2004-10-24
	# It won't do anything if there is already an input stream.(?)
	# 2004-10-16
	# Don't call deft_cgi() here. One way or another
	# code before this will make sure there's a valid eenv.
	#
		
	if (get_eenv($var_name))
	{
	    set_eenv("_return", 1);
	    my $val = get_eenv($var_name);
	}
	else
	{
	    set_eenv("_return", 0);
	}
	$result = get_eenv("_return");
    }
    return $result;
}


#
# We start off with no head_stream, in which case, one is created
# before execution starts. This enables all unwinds and rewinds to be identical.
# The last out stream is saved (and not cleaned) and becomes the next 
# head stream, if there is a next. This should allow states like "insert"
# to change columns in the stream, and the next state will be aware of the
# change without passing state info via CGI.
#
sub run_edges
{
    my $dbh = $_[0];
    my $gr_pk = $_[1];
    my $node_pk = $_[2];
    my $is_wait = 0;

    #
    # Init eenv with a call to deft_cgi().
    #
    # Run nodes until we run out of graph (an error) or
    # get to a wait node.
    #

    deft_cgi();

    while($node_pk > 0 && (! $is_wait))
    {
	my @e_array = sql_load_edges($dbh, $gr_pk, $node_pk);
	my $result = 0;
	my $to_node_fk = 0;

	#
	# Run edges until we find an edge that returns true.
	#
	
	while (! $result)
	{
	    my $edge_hr;
	    if (! ($edge_hr = shift(@e_array)))
	    {
		machine_error($dbh, "No more edges. node_pk was $node_pk");
	    }

	    my $source = $edge_hr->{source};
	    $to_node_fk = $edge_hr->{to_node_fk};
	    my $is_var = $edge_hr->{is_var};
	    my $var_name = $edge_hr->{code_var_name};
	    my $invert = $edge_hr->{invert};
	    $is_wait = $edge_hr->{is_wait};
	    
	    if ($is_var == 1)
	    {
		$result = test_vars($var_name);
	    }
	    else
	    {
		# Pass the $to_node_fk. run_core() knows that if this exists,
		# it needs to go into eenv as next_node, which will
		# always be preserved due to being hard coded in keep_core() in deftlib.pl

		$result = run_core($source, $to_node_fk); # deftlib.pl
	    }
	    if ($invert)
	    {
		$result = ! $result;
	    }
	}
	if ($to_node_fk <= 0)
	{
	    machine_error($dbh, "run_edges returns no new_node_pk. node_pk:$node_pk"); 
	}
	$node_pk = $to_node_fk;
    }
}

main:
{
    set_flag("single_task");

    # Set up paths and some global vars

    initdeft();

    my $query = new CGI();
    my %ch = $query->Vars();
    my %name_space; # key=code_name value=1
    my $node_pk;

    my $logname = `/usr/bin/id -nu`;
    chomp($logname);

    # 
    # ginfo parameter is comma separated list of 
    # graph name, logname, and node name i.e.
    # contentmgr,mst3k,draw_all
    # There is also a separate param next_node which is 
    # an integer node_pk.
    #
    
    #($ch{graph_name},$ch{next_node}) = split(',', $ch{ginfo});
    ($ch{graph_name}) = split(',', $ch{ginfo});

    if (! $ch{graph_name})
    {
	if ($#ARGV < 0)
	{
	    foreach my $arg (@ARGV)
	    {
		write_log("arg:$arg");
	    }
	    write_log("Error:Too few args.\nUsage:machine.pl graph_name [ nodename ]\n");
	    exit(1);
	}
	$ch{graph_name} = $ARGV[0];
    }

    my $dbh = deft_db_connect();

    (my $gr_pk, my $gr_path) = sql_gr_pk($dbh, $ch{graph_name}, $logname);
    chdir($gr_path);

    if (! $gr_pk)
    {
	write_log("No gr_pk. Probably bad graph name:$ch{graph_name}\n");
	machine_error($dbh, "(none). Bad gr_pk");
    }

    if (exists($ch{next_node}))
    {
	if (sql_node_ok($dbh, $gr_pk, $ch{next_node}))
	{
	    $node_pk = $ch{next_node};
	}
	else
	{
	    write_log("Node not ok gr_pk:$gr_pk nn:$ch{next_node}");
	}
    }

    if (! $node_pk)
    {
	$node_pk = sql_initial_node_pk($dbh, $gr_pk);
    }

    if (! $node_pk)
    {
	
	machine_error($dbh, "Unable to get valid starting node for gr_pk:$gr_pk");
    }

    run_edges($dbh, $gr_pk, $node_pk);
    machine_exit($dbh);
}
