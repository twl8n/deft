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
use Getopt::Long;
use Cwd qw(abs_path getcwd);

my $path = "./";
if ($0 =~ m/(.*)\//)
{
    $path = $1;
}
$path = abs_path($path);
$::_d_path = $path;

require "$path/sql_lib.pl";
require "$path/st_lib.pl";
require "$path/dcslib.pl";
require "$path/runtlib.pl";
require "$path/runt.pl";
require "$path/common_lib.pl";
require "$path/runt_compile.pl";

main:
{
    set_flag("single_task");

    initdeft();

    my $command;
    my %opts;
    #my $rc = GetOptions(\%opts, 'config=s');
    #    print "config:$opts{config}\n";
    #     foreach my $cl_arg (@ARGV)
    #     {
    # 	print "cla:$cl_arg\n";
    #     }
    
    (my $all_lines, my $fdate) = read_deft($ARGV[0]);
    
    my $dbh = system_dbh(); # deft_db_connect();
    # Scripts that need deft_cgi() must call it explicitly.
    my $rval = run_core($all_lines, 0, $ARGV[0]);
    $dbh->commit();
    clean_db_handles();
    exit(0);
}
