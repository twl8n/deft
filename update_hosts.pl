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

require "$path/common_lib.pl";
require "$path/sql_lib.pl";

main:
{
    my $dbh = system_dbh();

    #
    # Get the list of hosts from table config.
    # Check availability of each host via sub check_hosts() in deftlib.pl
    # Delete the old active_hosts from table config.
    # Insert the new active_hosts into table config.
    # 

    #
    # If there isn't a port in the config table, default is 9000.
    # If there aren't any hosts, default is ourself.
    # 

    my @temp = sql_config($dbh, "port");
    my $port;
    if ($#temp == -1)
    {
	$port = 9000;
	$temp[0] = $port;
	sql_update_config($dbh, "port", \@temp);
    }
    else
    {
	$port = $temp[0];
    }

    my @hosts = sql_config($dbh, "hosts");

    if ($#hosts == -1)
    {
	my $hostname = `/bin/hostname`;
	chomp($hostname);
	push(@hosts, $hostname);
    }
    my @active_hosts = check_hosts(\@hosts, $port);

    sql_update_hosts($dbh, \@active_hosts);

    $dbh->commit();
    $dbh->disconnect();
}
