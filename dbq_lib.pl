
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
use Socket;
use CGI;
use DBI  qw(:sql_types);
use Storable qw(freeze thaw);
use Cwd qw(abs_path getcwd);

my $out_stream_counter = 0;
sub next_stream
{
    $out_stream_counter++;
    return $out_stream_counter;
}

my @context_stack;
my %context;

sub read_context
{
    return ($context{dbh},
	    $context{host},
	    $context{port},
	    $context{top_in},
	    $context{in},
	    $context{out},
	    $context{code_id},
	    $context{fid});
}

sub set_context
{
    $context{dbh} = $_[0];
    $context{host} = $_[1];
    $context{port} = $_[2];
    $context{top_in} = $_[3];
    $context{in} = $_[4];
    $context{out} = $_[5];
    $context{code_id} = $_[6];
    $context{fid} = $_[7];
}


sub push_context
{
    my %tmp = %context;
    push(@context_stack, \%tmp); 
}

sub pop_context
{
    if ($#context_stack >= 0)
    {
	%context = %{pop(@context_stack)};
	return 1;
    }
    return 0;
}

my $dbh;
my $in_stream;
my $out_stream;
sub set_st_info
{
    $dbh = $_[0];
    $in_stream = $_[1];
    $out_stream = $_[2];
}

sub get_st_info
{
    return ($dbh, $in_stream, $out_stream);
}

my $cache_size = 500;
my %data_cache; # key=out_stream, array of hashes.
sub rewind
{
    my $rewind_now = $_[0];
    my $ba_index = $#{$data_cache{$out_stream}}+1;
    %{$data_cache{$out_stream}->[$ba_index]} = %{get_ref_eenv()};

    if ($rewind_now || (($ba_index+1) % $cache_size) == 0)
    {
	flush_rewind();
    }
    #write_log("rew> o:$out_stream");
    return 1;
}

sub flush_rewind
{
    #write_log("flush rewind in:$in_stream out:$out_stream dc:$#{$data_cache{$out_stream}}");
    if ($#{$data_cache{$out_stream}} >= 0)
    {
	my $data = freeze($data_cache{$out_stream});
	#my $len = length($data);
	sql_write($dbh, $out_stream, $data);
	$dbh->commit();
	@{$data_cache{$out_stream}} = ();
    }
}

# See implementation.txt for more detailed expostulation.
my @href;
my @uw_recs;
sub unwind
{
    clear_eenv();

    #write_log("uw: i:$in_stream");
    if ($#href == -1)
    {
	if ($#uw_recs == -1)
	{
	    #write_log("uw: sql_red with:$in_stream");
	    @uw_recs = sql_read($dbh, $in_stream);
	}
	if ($#uw_recs > -1)
	{
	    #write_log("uw: in:$in_stream uwr:$#uw_recs");
	    my $data = shift(@uw_recs);
	    @href = @{thaw($data)};
	    my $len = length($data);
	}
    }

    if ($#href > -1)
    {
	set_ref_eenv($href[0]);
	shift(@href);
	#write_log("uw true: i:$in_stream");
	return 1;
    }
    #write_log("uw false: i:$in_stream");
    return 0;
}

#
# This is what a bottom process does to eval its code.
# "bottom" is a relative term here. It includes the prime bottom,
# but also any process which is the bottom for a subroutine 
# (or eventually a block)
# 

sub dbq_eval
{
    my $dbh = $_[0];
    my $st_in = $_[1];
    my $st_out = $_[2];
    my $coderef = $_[3];
    
    #my $part = substr($coderef, 0, 10 );
    #write_log("ev> in:$st_in out:$st_out p:$part");

    set_st_info($dbh, $st_in, $st_out);

    {
	no strict;
	eval($coderef);
	if ($@)
	{
	    die $@;
	}
    }

    (my $dummy_dbh, $st_in, $st_out) = get_st_info();
    #set_st_info($dbh, $st_in, $st_out);
    flush_rewind();

    sql_inactivate_ancestor($dbh, $st_in, $st_out);
}


sub create_bottom
{
    (my $dbh,
     my $host,
     my $port,
     my $top_in,
     my $bottom_in, 
     my $bottom_out,
     my $code_id,
     my $fid) =  read_context();
        
    my $out;
    my $in;
    if ($bottom_out)
    {
	$out = $bottom_out;
    }
    else
    {
	$out = sql_new_stream_id($dbh);
    }
    $in = sql_new_stream_id($dbh);
    #write_log("cb> i:$in o:$out");
    $fid = sql_new_ancestor($dbh, $out, $in, "", $fid);

    # Our writer needs an ancestor whose out is our in.
    #write_log("cp> sna> i:$bottom_in o:$in");
    sql_new_ancestor($dbh, $in, $bottom_in, "", $fid);
    return ($in, $out, $fid);
}

#
# Spawn new processes.
# 

sub spawn_processes
{
    my $sub_name = $_[0];
    my $cb_flag = $_[1]; # create bottom ancestor
    my $sb_flag = $_[2]; # spawn bottom ancestor

    (my $dbh,
     my $host,
     my $port,
     my $dummy_top_in,
     my $bottom_in, 
     my $bottom_out,
     my $code_id,
     my $fid) =  read_context();

    my $exec = sql_get_code($dbh, $code_id);
    if ($cb_flag)
    {
	($bottom_in, $bottom_out, $fid) = create_bottom(); # reads context
    }

    my $aref = $exec->{$sub_name};

    my $in = $bottom_in;
    
    # pass 1
    my @anc;
    for(my $xx = ($#{$aref}-1); $xx>=0; $xx--)
    {
	my %tmp;
	my $out = $in;
	$in = sql_new_stream_id($dbh);
	
	$tmp{out} = $out;
	$tmp{in} = $in;
	$tmp{code} = $aref->[$xx];
	
	%{$anc[$xx]} = %tmp;

	my $part = substr($aref->[$xx], 0 , 10);
	#write_log("spa> xx:$xx in:$in out:$out p:$part");
    }

    #
    # Now switch top_in and bottom_in in order to correct
    # the new ancestor tree.
    #

    my $old_bottom_in = $bottom_in;
    my $top_in = $bottom_in;
    $bottom_in = $in; 
    
    #write_log("final> bi:$bottom_in ti:$top_in");
    
    if ($#{$aref} > 0)
    {
	$anc[0]->{in} = $top_in; # $bottom_in;
	$anc[$#{$aref}-1]->{out} = $bottom_in; # $top_in;
    }
    sql_update_bottom($dbh, 
		      $old_bottom_in,
		      $bottom_in,
		      $bottom_out,
		      $aref->[$#{$aref}]);

    # pass 2 (so we only have one commit)
    my $xx = 0;
    foreach my $info (@anc)
    {
	#write_log("p2> xx:$xx i:$info->{in} o:$info->{out}");
	sql_new_ancestor($dbh, $info->{out}, $info->{in}, $info->{code}, $fid);
	$xx++;
    }
    $dbh->commit();
    
    # pass 3
    foreach my $info (@anc)
    {
	#write_log("normal spawning> in:$info->{in}");
	$host = sql_next_host($dbh, $host);
	my $peer_handle = open_peer($host, $port);
	print $peer_handle "$info->{in},$code_id\n"; 
	close_peer($peer_handle);
    }

    if ($sb_flag)
    {
	#write_log("sb spawning> in:$bottom_in");
	$host = sql_next_host($dbh, $host);
	my $peer_handle = open_peer($host, $port);
	print $peer_handle "$bottom_in,$code_id\n"; 
	close_peer($peer_handle);
    }

    if (1)
    {
	set_context($dbh,
		    $host,
		    $port,
		    $top_in,
		    $bottom_in,
		    $bottom_out,
		    $code_id,
		    $fid);
    }

    # return top's input and bottom's out.
    return ($top_in, $bottom_out);
}


#
# needs to be called post-compile, pre-run time. e.g.
# process spawn time.
# might also be called at runtime under special circumstances?
#
 
sub call_deft
{
    my $sub_name = $_[0];

    (my $in, my $bottom_out) = spawn_processes($sub_name, 0, 0);

    (my $dbh,
     my $host,
     my $port,
     my $top_in,
     $in,
     my $out,
     my $code_id,
     my $fid) =  read_context();

    ($out, my $coderef) = sql_get_ancestor($dbh, $in);

    dbq_eval($dbh, $in, $out, $coderef);
}

# Not working yet.
sub if_col
{
    my $col = $_[0];
    my $sub_to_call = $_[1];
    
    (my $dbh,
     my $host,
     my $port,
     my $dummy_top_in,
     my $st_in,
     my $orig_out,
     my $code_id,
     my $fid) =  read_context();

    my %calling = spawn_processes($sub_to_call);

    #
    # Our last is context's out. Remember, inc_context runs
    # when we return.
    # Our out will be the called sub's in, so we make a new out stream.
    # 
    #$last = $out;
    # $out = next_stream();


    while(unwind())
    {
	if (get_eenv($col))
	{
	    # $::out_stream = $out;
	    set_st_info($dbh, $st_in, $calling{st_out});
	}
	else
	{
	    #$::out_stream = $last;
	    set_st_info($dbh, $st_in, $orig_out);
	}
	rewind();
    }
}

sub if_simple
{
    my $expr = $_[0];
    my $sub_to_call = $_[1];
    
    (my $dbh,
     my $host,
     my $port,
     my $dummy_top_in,
     my $st_in,
     my $last_out,
     my $code_id,
     my $fid) =  read_context();

    (my $sub_in, my $bottom_out) = ('','');
    #= spawn_processes($sub_to_call, 1, 1);

    #write_log("if_c> true:$sub_in false:$last_out");

    set_st_info($dbh, $st_in, $last_out);
    while(unwind())
    {
	no strict;
	restorevars();
	if (eval("$expr"))
	{
	    unless ($sub_in) 
	    {
		($sub_in, $bottom_out) = spawn_processes($sub_to_call, 1, 1);
	    }
	    set_st_info($dbh, $st_in, $sub_in);
	}
	else
	{
	    set_st_info($dbh, $st_in, $last_out);
	}
	rewind();

	#
	# reset st_info so that unwind will work
	# 

	set_st_info($dbh, $st_in, $last_out);
    }

    #
    # Flush the subroutine's in stream.
    # Inactivate my ancestor that writes to the subroutine.
    # Restore st_info for the our calling code.
    #

    set_st_info($dbh, $st_in, $sub_in);
    flush_rewind();
    sql_inactivate_ancestor($dbh, $st_in, $sub_in); # in, out
    set_st_info($dbh, $st_in, $last_out);
}

#
# rewind the input to N instances of $sub_to_call
# where N are the unique values of the columns @col_list.
# The subs all rewind to $last_out, however, agg_simple() 
# doesn't rewind anything to $last_out. In other words, all 
# of the output from agg_simple() goes to one of the instances
# of the subroutine.
#

sub agg_simple
{
    my $col_list = $_[0];
    my $sub_to_call = $_[1];
    
    (my $dbh,
     my $host,
     my $port,
     my $dummy_top_in,
     my $st_in,
     my $last_out,
     my $code_id,
     my $fid) =  read_context();

    my %unique;
    my $key_str = $col_list;
    $key_str =~ s/,/\$/g;
    $key_str = "\"\$$key_str\"";
    
    set_st_info($dbh, $st_in, $last_out);
    my $bottom_out;
    while(unwind())
    {
	no strict;
	restorevars();
	my $key = eval($key_str);
	if (! exists($unique{$key}))
	{
	    set_context($dbh,
			$host,
			$port,
			$dummy_top_in,
			$st_in,
			$last_out,
			$code_id,
			$fid);
	    ($unique{$key}, $bottom_out) = spawn_processes($sub_to_call, 1, 1);
	    #$unique{$key} = new_proc($sub_to_call);
	}
	set_st_info($dbh, $st_in, $unique{$key});
	rewind();

	#
	# reset st_info so that unwind will work
	# Huh? unwind uses $st_in, and that never changes.
	#

	set_st_info($dbh, $st_in, $last_out);
    }

    #
    # Flush the subroutines' in streams.
    # Inactivate ancestors that write to the subroutines.
    # Restore st_info for the our calling code (not necessary).
    #

    foreach my $item (keys(%unique))
    {
	set_st_info($dbh, $st_in, $unique{$item});
	flush_rewind();
	sql_inactivate_ancestor($dbh, $st_in, $unique{$item}); # in, out
    }
    set_st_info($dbh, $st_in, $last_out);
}


1;
