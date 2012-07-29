#!/opt/local/bin/perl -w

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

require "$path/dbq_lib.pl";
require "$path/dbq_sql_lib.pl";
require "$path/sql_lib.pl";
require "$path/common_lib.pl";

main:
{
    if (1)
    {
	#
	# If true STDERR will go to /var/log/messages
	# This is practicaly a requirement for xinetd created daemons.
	# Also important for debugging processes that aren't attached to ttys.
	# 
	if (! open(STDERR, "| /usr/bin/logger -i -t deftd_err"))
	{
	    write_log("can't pipe stderr to logger\n");
	    exit(1);
	}
	if (! open(STDOUT, "| /usr/bin/logger -i -t deftd_out "))
	{
	    write_log("can't pipe stdout to logger\n");
	    exit(1);
	}
    }

    initdeft();
    my $peer_info = <>; # stdin has the unwind stream id
    chomp($peer_info);

    (my $st_in, my $code_id) = split(',', $peer_info);

    my $dbh = system_dbh();

    (my $st_out, my $coderef, my $fid) = sql_get_ancestor($dbh, $st_in);
    
    my $part = substr($coderef, 0, 10);
    #write_log("d> in:$st_in o:$st_out p:$part");

    if (! $st_out || ! $st_in)
    {
	#write_log("Didn't get streams. st_in:$st_in st_out:$st_out\n");
	clean_db_handles();
	exit(1);
    }

    set_st_info($dbh, $st_in, $st_out);
    set_context($dbh, "", 9000, $st_in, $st_in, $st_out, $code_id, $fid);

    {
	no strict;
	eval($coderef);
	if ($@)
	{
	    die "$@\ndeftd.pl err:$coderef\n";
	}
    }

    (my $dummy_dbh, $st_in, $st_out) = get_st_info();
    #set_st_info($dbh, $st_in, $st_out);

    flush_rewind();

    #
    # Not really an ancestor. We're supposed to be inactivating our 
    # output. In other words, we're done rewinding. Should be called
    # something like "output_done".
    #

    sql_inactivate_ancestor($dbh, $st_in, $st_out);

    $dbh->commit();
    clean_db_handles();
    exit(0);
}


