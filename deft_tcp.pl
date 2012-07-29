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
require "$path/runt_compile.pl";

main:
{
    clear_flag("single_task"); # I know it isn't set. This clarifies things.
    set_flag("last_task");     # We are last of process chain.
    initdeft();
    #my %opts;
    #my $rc = GetOptions(\%opts, 'config=s');
    #    print "config:$opts{config}\n";
    #     foreach my $cl_arg (@ARGV)
    #     {
    # 	print "cla:$cl_arg\n";
    #     }
    
    my @stat_array = stat("$ARGV[0]");
    my $size = $stat_array[7];
    open(IN, "<",  "$ARGV[0]");
    sysread(IN, my $all_lines, $size);
    close(IN);
    
    my $dbh = system_dbh();

    my $exec = compile_deft($all_lines);
    
    #
    # The last $aid is the aid of this process.
    # Remember, we build the ancestor chain backwards.
    # 
    my $aid = sql_new_stream_id($dbh);
    deft_cgi();
    sql_rewind($dbh, $aid);
    sql_inactivate_ancestor($dbh, $aid);
    my @aid_list;
    my $fid = 0;
    foreach my $an_code (@{$exec->{main}})
    {
	push(@aid_list, $aid);
	my $nok = $aid;
	$aid = sql_new_stream_id($dbh);
	if (!$fid)
	{
	    $fid = sql_new_ancestor($dbh, $nok, $aid, "$an_code", 0);
	}
	else
	{
	    sql_new_ancestor($dbh, $nok, $aid, "$an_code", $fid);
	}
    }
    $dbh->commit();

    #
    # 2005-01-06
    # $peer_handle is output tcp stream
    # STDIN is our input tcp stream
    # $aid is ancestor id which is myself.
    # $nok is next of kin which is my next ancestor up the chain.
    # 

    # Yes, I know that $fid already has a the same value. 
    (my $nok, my $coderef, $fid) = sql_get_ancestor($dbh, $aid);

    my $host = sql_next_host($dbh);
    my @temp = sql_config($dbh, "port");
    my $port = $temp[0];
    my $peer_handle = open_peer($host, $port); # should get host info from db
    print $peer_handle "$nok\n";

    #
    # This never needs to do an ancestor_unwind() because there is
    # always at last one line of code, and if there is only one line, then
    # there are two processes and the other one will do the ancestor_unwind().
    # 
    {
	no strict;
	eval($coderef);
	if ($@)
	{
	    die $@;
	}
    }

    # 
    # Don't pop or otherwise mess with @ancestor_streams, or they won't
    # all be cleaned up.
    # 
    close_peer($peer_handle);
    #sql_duo_clean($dbh, \@aid_list, 1);
    $dbh->commit();
    clean_db_handles();
    exit(0);
}
