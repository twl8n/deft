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

require "$path/deft_tcp_lib.pl";
require "$path/tcp_sql_lib.pl";
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
	if (! open(STDERR, "| /usr/bin/logger -i -t deftd"))
	{
	    write_log("can't pipe stderr to logger\n");
	    exit(1);
	}
    }

    initdeft();
    my $aid = <>; # stdin has the unwind stream id
    chomp($aid);  # egads.

    if (! $aid)
    {
	write_log("deftd_tcp.pl no aid");
	exit(1);
    }

    my $dbh = system_dbh();
    (my $nok, my $coderef) = sql_get_ancestor($dbh, $aid);
    write_log("daemon aid:$aid cr:$coderef");

    my $cp_flag = 0;
    if ($coderef)
    {
	my $host = sql_next_host($dbh);
	my @temp = sql_config($dbh, "port");
	my $port = $temp[0];
	my $peer_handle = open_peer($host, $port);
	print $peer_handle "$nok\n";
	$cp_flag = 1;
	# close_peer() later because we rewind to stdout
    }

    # 
    # If we don't have code, then do an ancestor unwind, which is
    # currently implemented as unwinding from the db. The oldest ancestor
    # exists only to get the stream going for the rest of the family.
    #
    # Note that checking $@ works for some errors, but the perlfunc man page
    # says that it won't work for everything. 
    # 
    if (! $coderef)
    {
	my $sth = sql_read_prep($dbh, $aid);
	while(sql_unwind($dbh, $sth, $aid))
	{
	    rewind();
	}
    }
    else
    {
	no strict;
	eval($coderef);
	if ($@)
	{
	    die "$@\ndeftd.pl err:$coderef\n";
	}
    }
    # Not really an ancestor. We're supposed to be inactivating our 
    # output. In other words, we're done rewinding. Should be called
    # something like "output_done".
    #
    sql_inactivate_ancestor($dbh, $aid);
    if ($cp_flag)
    {
	close_peer();
    }
    $dbh->commit();
    clean_db_handles();
    exit(0);
}


