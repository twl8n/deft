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

my $path = "./";
if ($0 =~ m/(.*)\//)
{
    $path = $1;
}
$path = abs_path($path);
$::_d_path = $path;

require "$path/sql_lib.pl";
require "$path/stll_lib.pl";
require "$path/dcslib.pl";
require "$path/runtlib.pl";
require "$path/runt.pl";
require "$path/common_lib.pl";
require "$path/runt_compile.pl";

main:
{
    initdeft();

    foreach my $arg (@ARGV)
    {
	(my $all_lines, my $fdate) = read_deft($arg);
	my $output = compile_all($all_lines);

	my $stem;
	if ($arg =~ m/(.*)\.deft/)
	{
	    $stem = $1;
	}
	else
	{
	    $stem = $arg;
	}

	# Check that the .pl file we're overwriting
	# looks like one of our files.
	my $a_dot_out = a_dot_out($stem); # C compilers are funny.

	open(OUT, "> $a_dot_out") || die "Can't open $a_dot_out\n";
	print OUT $output;
	close(OUT);
	chmod 0755, $a_dot_out;

	print "$a_dot_out\n";
    }
}
