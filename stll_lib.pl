
# Single tasking (st) linked list (ll) stream library. Ok, but then
# what is st_lib.pl? Some kind of generic stream library?

# This is part of Deft.

#Copyright (C) 2012 Tom Laudeman, Noah Healy.

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
#use Cwd qw(abs_path getcwd);
use Data::Dumper;
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);


# Locally scoped globals necessary
# for the single process version of rewind.

my $frame = 0;   # stack frame $table[row][frame]
my $stream_head = 0;
my $curr_eeref = 0;

# Holds current row counter in @table.
my $rowc = 1;

# The data table. Probably don't need curr_eeref or stream_head.
# my @table;

# Clean up from wrong_think_memoizing_rewind(). See wrong_think_memoizing_rewind below.
sub postusevars
{
    foreach my $var (user_keys_eenv())
    {
 	no strict;
 	$$var = undef;
    }
}

my $uw_flag = 1;
sub go_unwind
{
    $uw_flag = 1;
}


# Insert a new, empty record. Should only be called as part of table initialization.
# Set the eeref of the new record.

sub dumpt
{
    return Dumper(\@::table);
}

sub insert_rec
{
    my $newr = [{}];
    push(@::table, $newr);
    # set_ref_eenv(${$newr}[0]);
    set_ref_eenv($::table[$#::table][0]);
}

sub dup_insert
{
    # What should happen if we are asked to dup_insert when there
    # is no record to dup? Well, that must never happen.
    clone();
}

sub stream_head
{
    return $stream_head;
}

sub get_frame
{
    return $frame;
}

sub curr_rec
{
    # If there aren't any table rows, create one.
    if ($#::table == -1)
    {
        return clone();
    }
    return \%{$::table[$#::table][get_frame()]};

    # Old:
    # # This might have been a debug and not real code. Zero is the
    # # value for no more records.
    
    # # Previously, the if-die was in unwind(). If unwind() doesn't want
    # # a zero value, then noone else does either.
    # if ($curr_eeref == 0)
    # {
    #     # die;
    # }
    # return $curr_eeref;
}



# Move a record to the stream head, and set the _last_rec if
# $_[0]. Essentially, this creates a new virtual stream in the table.

# See _old_next below. $myself remains curr_eeref, and next_rec()
#knows about the extra link.

sub move_rec
{
    my $myself = get_ref_eenv();

    # patch prev and next, essentially removing myself.
    my $prev = get_eenv("_prev_rec");
    my $next = get_eenv("_next_rec");
    # my $on = get_eenv("_old_next");


    # Order dependent! Set _old_next of $myself before any changes to
    # curr_eeref or calls to set_ref_eenv(); If _old_next is not
    # properly detected in next_rec(), the bug is probably right here.

    set_eenv("_old_next", $next);

    if ($next)
    {
	set_ref_eenv($next);
	if ($prev)
	{
	    set_eenv("_prev_rec", $prev);
	}
	else
	{
	    # Don't allow undef.
	    set_eenv("_prev_rec", 0);
	}
    }
    #print "mr next: $next on: $on\n";

    if ($prev)
    {
	set_ref_eenv($prev);
	if ($next)
	{
	    set_eenv("_next_rec", $next);
	}
	else
	{
	    # Don't allow undef.
	    set_eenv("_next_rec", 0);
	}
    }
    # insert before stream_head
    if ($myself != stream_head())
    {
	set_ref_eenv($myself);
	set_eenv("_next_rec", stream_head());
	set_ref_eenv(stream_head());
	set_eenv("_prev_rec", $myself);
    }

    # myself becomes the new stream head.
    $stream_head = $myself;

    # If we are the first record in this "stream" then set _last_rec

    if ($_[0])
    {
	set_ref_eenv(stream_head());
	set_eenv("_last_rec", 1);
    }
#     my $nx = get_eenv("_next_rec");
#     print "move cr: $curr_eeref on: $next nx: $nx\n";
}


sub next_rec
{
    # If there is no next record, $curr_eeref will be zero. Using zero as
    # empty/null record pointers is an important convention.
    
    if ($curr_eeref == 0)
    {
	# print "begin next_rec zero\n";
	return 0;
    }

    # Cope with records that move, and have a link to their old next
    # record. Use _old_next preferentially, and then zero it
    # out. Could even undef it, but that might be less efficient.

    my $orig = $curr_eeref;
    set_ref_eenv($curr_eeref);
    if (exists_eenv("_old_next"))
    {
	$curr_eeref = get_eenv("_old_next");
	clear_var_eenv("_old_next");
	#print "next_rec orig: $orig old cr: $curr_eeref\n";
    }
    else
    {
	$curr_eeref = get_eenv("_next_rec");
	#print "next_rec orig: $orig new cr: $curr_eeref\n";
    }
    if ($curr_eeref == 0)
    {
	# print "end next_rec zero\n";
	return 0;
    }
    set_ref_eenv($curr_eeref);
    return $curr_eeref;
}

sub reset_stream
{
    treset();
    # Not used? Still compiled in.
    # $curr_eeref = $stream_head;
}


# Use a local global or something so we don't have to pass a hash ref
# to unwind just for the view list. Thankfully this gets rid of that
# damned $urh.

# Make this more efficient later.

my @view_list;

sub view_list
{
    return \@view_list;
}

sub set_view_list
{
    undef(@view_list); # clear it or something. 
    foreach my $item (@_)
    {
	push(@view_list, $item);
    }
}


# Mark records that will be processed. Dups of these records will not
# be run, but will get copies of columns from the memoz records during
# the rewind phase.

# Figure out what columns we're interested in. Make a key, and save
# the value of the parent record eenv as the value. Set the parent
# record's _memoz to zero. Child records have the parent eenv in their
# _memoz field.

# Use slice_key() to get a reference key for each record. Keep a
# unique hash list, and save the keys. I'm guessing that columns
# could get munged and we'd "lose" the record key. So save the rk
# so we won't lose it.

# As a happy side effect, the _memoz column becomes zero for the
# parent record, and $eeref for child records.

# This could use curr_rec() instead of $eeref.

# (This may not be true.) At the end, set the current record back to
# the original. We might be in a sub-stream, and we need to return to
# the head of the sub-stream, not the stream head of the whole table.

# Noah says an empty column/key works fine for memoz.

sub memoz
{
    # this needs a full rewrite.
    return ;

    my %rec_keys;
    my $vlist_r = view_list();
    print "vlr: " . Dumper($vlist_r) . "\n";
    print "getting eeref\n";
    my $eeref = curr_rec();
    my $orig_eeref = $eeref;
    my $go = 1;
    while ($eeref && $go)
    {
	set_ref_eenv($eeref);
	my $uw_last = get_eenv("_last_rec");
	if ($uw_last)
	{
	    $go = 0;
	}

        # rk: reference key
	my $rk = slice_key($vlist_r);
	set_eenv("_rk", $rk);
	if (!exists($rec_keys{$rk}))
	{
	    set_eenv("_memoz", 0);
	    $rec_keys{$rk} = $eeref;
	}
	else
	{
	    printf("reference key rk: $rk for view list: %s\n", Dumper($vlist_r));
	    set_eenv("_memoz", $rec_keys{$rk});
	}
	# printf("mem: %s rk: $rk get_eenv: %s\n", Dumper($eeref), get_eenv("_memoz"));
        $Data::Dumper::Maxdepth = 1;
	printf("xrk: $rk get_eenv: %s\n", Dumper(get_eenv("_memoz")));
	$eeref = next_rec();
    }
    $curr_eeref = $orig_eeref;
}

# Copy columns from the parent memoz record into the current (child) record. This should be called exclusively
# from unwind(). This is the other end of memoz().

sub copy_view_list
{
    my $parent_eeref = get_eenv("_memoz");
    my $vl_ref = view_list();

    # print "self: $eenv parent: $parent_eeref\n";
    my $output ;
    foreach my $var (@{$vl_ref})
    {
	# $output .= " $var old: ". $eenv->{$var} new: $parent_eeref->{$var}\n";
	# $eenv->{$var} = $parent_eeref->{$var};
	$output .= " $var old: ". get_eenv($var) . " new: $parent_eeref->{$var}\n";
	set_eenv($var, $parent_eeref->{$var});
    }
    # $eenv->{alias("_memoz")} = 0;
    set_eenv('_memoz', 0);

}


sub rewind
{
    # Do not reset $rowc here. 
}

# There is a closure unwind in code_archive.txt.

# Need the while(1) so that memoized rows will be processed via copy_view_list() and we'll get the next real
# row of data. This depends on next and return which are very like goto. But this is not considered the least
# bit harmful.

sub unwind
{
    if ($rowc >= 0)
    {
        set_ref_eenv($::table[$rowc][0]);
        # printf("uwref: %ld\n", $::table[$rowc][0]);
        $rowc--;
        print "rowc: $rowc\n";
        return 1;
    }
    return 0;

    # while ($rowc > 0)
    # {
    #     $rowc--;
    #     set_ref_eenv(($::table[$rowc][get_frame()]));
    #     if (get_eenv("_memoz"))
    #     {
    #         copy_view_list(); # sub above. Clears _memoz.
    #         next;
    #     }
    #     if ($rowc >= 0)
    #     {
    #         return 1;
    #     }
    #     return undef;
    # }
    # return undef;
}


# Stream specific unwind. s_unwind(2) will only unwind rows in stream 2.
sub s_unwind
{
    # print "unwind: $rowc max: $#table\n";
    # In try.pl we needed >=
    # while ($rowc >= 0)
    while ($rowc > 0)
    {
        $rowc--;
        set_ref_eenv(($::table[$rowc][get_frame()]));
        if (get_eenv('_stream') != $_[0])
        {
            next;
        }
        if (get_eenv("_memoz"))
        {
            copy_view_list(); # sub above. Clears _memoz.
            next;
        }
        if ($rowc >= 0)
        {
            return 1;
        }
        return undef;
    }
    return undef;
}

sub tell_streams
{
    treset();
    my %stname;
    while(unwind())
    {
        if (! exists($stname{get_eenv('_stream')}))
        {
            $stname{get_eenv('_stream')} = 1;
        }
    }
    print "Active streams: ";
    my $tween = "";
    foreach my $key (sort(keys(%stname)))
    {
        print "$tween$key";
        $tween = ", ";
    }
    print "\n";
}

sub clone
{
    # See dup_insert() used in dcslib.pl sub read_tab_data(). Might be an older version of clone.

    # A oneliner to try an anon list of hash
    # perl -e 'use Data::Dumper; $newr = [{}]; print Dumper($newr);'

    # Probably only not defined when get_frame() returns zero. Otherwise might be trouble.

    # See insert_rec() for code that inserts a new empty record.

    my $newr = dclone(\@{$::table[$rowc]});
    push(@::table, $newr);
    set_ref_eenv(${$newr}[0]);
    return \%{$::table[$#::table][get_frame()]};
}

# Exactly like new rewind(), but reset_stream() calls this and reset_stream() is emitted by the compiler.

# This might need to be in some code that the compiler always emits immediately before unwind() like
# inc_stream() or something.

# There is an existing Perl keyword reset() so we have to use another name.
# Conflicting keyword silently fails in this case. 

sub treset
{
    $rowc = $#::table;
    print "treset (rewind): $rowc\n";
}


sub spawn_processes
{
    my @lines = @{$_[0]};

    (my $dummy,
     my $last_in,
     my $out,
     my $last) = read_context();

    #
    # Add to context stack (do not replace top of stack).
    # Build backwards from last line, pushing onto context stack.
    # This results in streams being numbered backwards
    # e.g. as execution goes, stream numbers decrease.
    #

    my $in;
    for(my $xx = $#lines; $xx>=0; $xx--) # my $line (@lines)
    {
	my $line = $lines[$xx];
	if ($xx == 0)
	{
	    $in = $last_in;
	}
	else
	{
	    $in = next_stream();
	}
	set_context($line,  	# code
		    $in,	# in
		    $out,	# out
		    $last);	# last
	push_context();
	$out = $in;
    }
    return $in;
}

1;
