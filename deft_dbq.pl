#!/opt/local/bin/perl

# This is part of Deft and the DeFindIt Classic Search engine.

#Copyright (C) 2003,2004,2005 Tom Laudeman, Noah Healy.

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
use Getopt::Long;
use Cwd qw(abs_path getcwd);

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

require "$path/dbq_sql_lib.pl";
require "$path/sql_lib.pl";
require "$path/dbq_lib.pl";
require "$path/common_lib.pl";
require "$path/runt_compile.pl";

main:
{
    clear_flag("single_task"); # I know it isn't set. This clarifies things.
    set_flag("last_task");	# We are last of process chain.
    set_flag("dbq");		# use database streams

    initdeft();

    (my $all_lines, my $fdate) = read_deft($ARGV[0]);

    my $dbh = system_dbh();

    (my $dummy, my $exec) = compile_deft($all_lines);
    my $code_id = sql_save_code($dbh, $exec);
    my @ports = sql_config($dbh, "port"); # sql_config always returns an array.
    my $port = $ports[0];	# we only need one port.

    set_context($dbh,
		"",
		$port,
		0,
		0,
		0,
		$code_id,
		0);

    # create_bottom=1, spawn_bottom=0
    (my $top_in, my $bottom_out) = spawn_processes("main", 1,0);

    (my $dummy_dbh,
     my $dummy_host,
     my $dummy_port,
     my $dummy_top_in,
     my $bottom_in, 
     $bottom_out,
     $code_id,
     my $fid) =  read_context();

    #write_log("b> ti:$top_in dti:$dummy_top_in i:$bottom_in o:$bottom_out");
    #
    # rewind zeroth table to the first ancestor (top of the tree).
    # The top will unwind from that out.
    #

    deft_cgi();
    set_st_info($dbh, 0, $top_in);

    rewind(1); # rewind now.

    sql_inactivate_ancestor($dbh, 0, $top_in); # in, out

    $dbh->commit();

    (my $dummy_out, my $coderef) = sql_get_ancestor($dbh, $bottom_in);

    dbq_eval($dbh, $bottom_in, $bottom_out, $coderef);

    sql_fid_clean($dbh, $fid);
    
    $dbh->commit();
    clean_db_handles();
    exit(0);
}
