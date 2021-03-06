
# This is part of Deft and the DeFindIt Classic Search engine.

#Copyright (C) 2007 Tom Laudeman, Noah Healy.

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
use FindBin;
use lib "$FindBin::Bin";
use session_lib;
#use Cwd qw(abs_path getcwd);

# stack list of the subroutines currently active.
my @sub_stack;

my $main_str = "main:"; # this changes way too often.

my @table;       # the table $table[row][scope] where current scope is the zeroth element

my %deft_func;   # See sub initdeft

my $eenv;        # Hash ref of the current row
my %is_dsub;     # key is sub name, value is 1
my %args;        # key is sub name, value is a hash of arg names.
my %is_top;      # indexes of Deft (table operating) subs.

my $tc = 1; # valid wrap values are non-zero
my $wrap_scalar = $tc++;
my $wrap_top = $tc++;
# my $wrap_ifs = $tc++; # Old?
my $wrap_none = $tc++;
my $wrap_delete = $tc++;
my $wrap_perl = $tc++;
my $wrap_sub = $tc++;
my $wrap_sub_start = $tc++;
my $wrap_sub_stop = $tc++;
my $wrap_main = $tc++;
my $wrap_main_start = $tc++;
my $wrap_main_stop = $tc++;
my $wrap_dsub = $tc++; # User written deft sub
my $wrap_merged = $tc++;
my $wrap_ags = $tc++;
my $wrap_ags_start = $tc++;
my $wrap_ags_stop = $tc++;
my $wrap_if = $tc++;
my $wrap_if_start = $tc++;
my $wrap_if_else = $tc++; # added during compile phase
my $wrap_if_welse_start = $tc++; # added during compile phase
my $wrap_else = $tc++;
my $wrap_else_start = $tc++;
my $wrap_elsif = $tc++;
my $wrap_elsif_start = $tc++;
my $wrap_elsif_else = $tc++;
my $wrap_elsif_welse_start = $tc++;
my $wrap_if_stop = $tc++;
my $wrap_if_welse_stop = $tc++;
my $wrap_else_stop = $tc++;
my $wrap_union = $tc++;
my $wrap_union_start = $tc++;
my $wrap_union_stop = $tc++;
my $wrap_comment = $tc++;

# List of start types for various block statements.
# ALL block types need to be here (and almost certainly in @end_type).

my @start_type;
$start_type[$wrap_sub] = $wrap_sub_start;
$start_type[$wrap_main] = $wrap_main_start;
$start_type[$wrap_ags] = $wrap_ags_start;
$start_type[$wrap_if] = $wrap_if_start;
$start_type[$wrap_if_else] = $wrap_if_welse_start;
$start_type[$wrap_else] = $wrap_else_start;
$start_type[$wrap_elsif] = $wrap_elsif_start;
$start_type[$wrap_elsif_else] = $wrap_elsif_welse_start;
# start of wrap_union isn't used.
$start_type[$wrap_union] = $wrap_union_start;

my @end_type;

$end_type[$wrap_main] = $wrap_main_stop;
$end_type[$wrap_sub] = $wrap_sub_stop;
$end_type[$wrap_ags] = $wrap_ags_stop;
$end_type[$wrap_if] = $wrap_if_stop;
$end_type[$wrap_if_else] = $wrap_if_welse_stop;
$end_type[$wrap_else] = $wrap_else_stop;
$end_type[$wrap_elsif] = $wrap_if_stop;
$end_type[$wrap_elsif_else] = $wrap_if_stop;
# end of wrap_union isn't used.
$end_type[$wrap_union] = $wrap_union_stop;

my @w2t; # wrap-to-text translation
$w2t[$wrap_scalar] = "scalar";
$w2t[$wrap_top] = "top";
$w2t[$wrap_none] = "none";
$w2t[$wrap_delete] = "delete";
$w2t[$wrap_perl] = "perl";
$w2t[$wrap_sub] = "sub";
$w2t[$wrap_sub_start] = "sub_start";
$w2t[$wrap_sub_stop] = "sub_stop";
$w2t[$wrap_main] = "main";
$w2t[$wrap_main_start] = "main_start";
$w2t[$wrap_main_stop] = "main_stop";
$w2t[$wrap_dsub] = "dsub";
$w2t[$wrap_merged] = "merged";
$w2t[$wrap_ags] = "ags";
$w2t[$wrap_ags_start] = "ags_start";
$w2t[$wrap_ags_stop] = "ags_stop";
$w2t[$wrap_if] = "if";
$w2t[$wrap_if_start] = "if_start";
$w2t[$wrap_if_else] = "if_else";
$w2t[$wrap_if_welse_start] = "if_welse_start";
$w2t[$wrap_else] = "else";
$w2t[$wrap_else_start] = "else_start";
$w2t[$wrap_elsif] = "elsif";
$w2t[$wrap_elsif_start] = "elsif_start";
$w2t[$wrap_elsif_else] = "elsif_else";
$w2t[$wrap_elsif_welse_start] = "elsif_welse_start";
$w2t[$wrap_if_stop] = "if_stop";
$w2t[$wrap_if_welse_stop] = "if_welse_stop";
$w2t[$wrap_else_stop] = "else_stop";
$w2t[$wrap_union] = "union";
$w2t[$wrap_union_start] = "union_start";
$w2t[$wrap_union_stop] = "union_stop";
$w2t[$wrap_comment] = "comment";


# This is a simple and crude method to make variable argument lists
# for Deft TOP calls. This will almost certainly have to be fixed some
# day.

sub list
{
    return join(',',@_);
}

# This is pretty naive, but should work for now.
# require must be at the beginning of the line.
# the file name must be inside double quotes.

sub read_deft
{
    my $file_name = $_[0];
    my @fdate; 

    (my $all_lines, $fdate[0]) = read_file($file_name, 2);

    my @rec_list;
    while($all_lines =~ s/^require\s+\"(.*)\";//g)
    {
	push(@rec_list, $1);
    }
    my $xx = 1;
    foreach my $fn (@rec_list)
    {
	(my $more_lines, $fdate[$xx]) = read_file($fn, 2);
	$all_lines .= $more_lines;
	$xx++;
    }

    # Sort dates descending. We want the most recent date to be $fdate[0].
    my @sorted_dates = sort {$b <=> $a} @fdate;

#     {
# 	my $cwd = `/bin/pwd`; chomp($cwd);
# 	write_log("$0 Cannot open $file_name for read. pwd is $cwd");
# 	exit(1);
#     }

    my @lt = localtime($sorted_dates[0]); 
    my $date = sprintf("%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d",
		       1900+$lt[5],$lt[4]+1,$lt[3],$lt[2],$lt[1],$lt[0]);

    return ($all_lines, $date);
}




# keep_row() was ancient and seriously out of datte
# and therefore broken. Moved to code archive.

# Useful for creating aggragating subroutine for library like 
# functions mnemonic Declare Unique Column
# usage duc('column_name');

sub duc
{
    my $seed = 'A';
    my %urh;
    while (unwind(\%urh))
    {
	set_eenv($_[0],$seed);
	$seed++;
	rewind(\%urh);
    }
}

sub rerel
{
    # Needs some commentary. Since this is only called from life.deft, we might assume that it is
    # purpose-specific code. It might do the equivalent of the following self_select():
    
    # self_select('state as neighbor, x_cord as x_n, y_cord as y_n',
    #             'abs($x_n - $x_cord) < 2 && abs($y_n - $y_cord) < 2 && ($y_n != $y_cord || $x_n != $x_cord)');  
    
    my @ttable;
    while(unwind_simple())
    {
        push(@ttable, get_ref_eenv());
    }
    
    foreach my $ii (0..$#ttable)
    {
        my $flag = 0;
        set_ref_eenv($ttable[$ii]);
        
        # Set value of the non-declared rerelating columns
        # for the expression evaluation. We need these columns
        # when we eval the expression.

        # This relies on two cols with fixed identities: x_cord, y_cord.
        
        my $x_cord = get_eenv("x_cord");
        my $y_cord = get_eenv("y_cord");
        
        foreach my $jj (0..$#ttable)
        {
            set_ref_eenv($ttable[$jj]);
            
            # Values of the declared rerelating columns. If the
            # expression is true, we carry these values to the $ii
            # row.
            
            my $x_n = get_eenv("x_n");
            my $y_n = get_eenv("y_n");
            my $neighbor = get_eenv("neighbor");
            
            # The expression is the clause of the if. For now assume
            # that expression must eval to a boolean. Must not change
            # the value of any columns.
            
            if (abs($x_n - $x_cord) < 2 &&
                abs($y_n - $y_cord) < 2 &&
                ($y_n != $y_cord ||
                 $x_n != $x_cord))
            {
                set_ref_eenv($ttable[$ii]);
                $flag = 1;
                
                # Carry values from row $jj to row $ii.
                
                set_eenv("x_n", $x_n);
                set_eenv("y_n", $y_n);
                set_eenv("neighbor", $neighbor);
                
                rewind_simple();
            }
            
        }
        
        if (! $flag)
        {
            set_ref_eenv($ttable[$ii]);
            
            # No relationship, keep row, cols become null.  The
            # expression was false for all $jj rows tested against for
            # the current $ii row.
            
            set_eenv("x_n", "");
            set_eenv("y_n", "");
            set_eenv("neighbor", "");
            
            rewind_simple();
        }
    }
}




# This makes the potentially dangerous assumption that $sub_call is a
# complete and correct subroutine invocation, including the arg
# list. There has to be a better way.

sub naive_make_col
{
    my $col = $_[0];
    # switching order of these args
    # old order unusable
    my $sub_call = $_[1];
    my $default = $_[2];

    my %urh;
    my $run_once =1;
    while(unwind(\%urh) || $run_once)
    {
	$run_once = 0;
	restorevars();
	my $eref = get_ref_eenv();
	my @list;
	{
	    no strict;
	    @list = eval("$sub_call");
	    # print "l:$#list c:$col s:$sub_call\n";
	}
	if ($#list >= 0)
	{
	    foreach my $item (@list)
	    {
		set_ref_eenv($eref); # Noah says: This is a continuation. Aren't you pleased?
		set_eenv($col, $item);
		rewind(\%urh);
	    }
	}
	else
	{
	    set_eenv($col, $default);
	    rewind(\%urh);
	}
    }
}


# This exists specifically to break apart \0 joined CGI values and
# make a new row for each value.  List elements of each split col
# correspond to each other, and were grouped in the original form
# (otherwise this makes no sense).

sub cgi_make_row
{
    my $col_list_str = $_[0];

    my @col_list = split(',', $col_list_str);

    # Tom: I don't think this should run_once because it doesn't 
    # make rows from external sources.
    #my $run_once = 1;
    my %urh;
    while(unwind(\%urh)) #  || $run_once)
    {
	#$run_once = 0;
	#restorevars();
	my %l_hash;
	my $c_max = -1;
	foreach my $col (@col_list)
	{
	    {
		no strict;
		#@{$l_hash{$col}} = split('\0', $$col);
		@{$l_hash{$col}} = split('\0', get_eenv($col));
		if ($c_max < $#{$l_hash{$col}})
		{
		    $c_max = $#{$l_hash{$col}};
		}
	    }
	}
	
	if ($c_max >= 0)
	{
	    for(my $xx=0; $xx<=$c_max; $xx++)
	    {
		foreach my $col (@col_list)
		{
		    my $value = shift(@{$l_hash{$col}});
		    set_eenv($col, $value);
		}
		rewind(\%urh);
	    }
	}
	else
	{
	    rewind(\%urh);
	}
    }
}


# dec 22 2013 Need to expunge *depth since the table doesn't have that concept any more. We unshift/shift
# stack frames onto the table, so the current stack frame is always $table[rows][0], where the current scope
# is zero.

# dec 28 2006 currently in use, and has been used for some time
# Clean up local cols created by Deft subroutines.
# The original version relied on %depth_vars to track which vars
# where active at the current depth. Any vars at get_depth() +1 
# are removed. This assumes that depth can only change by +1 or -1.

# This plan is weak and not supported get_eenv() and get_ref_eenv().
# Also, since this method does not have actual unique column names for
# local cols, a local col will write into rows of the global column.

sub garbage_collection
{
    # We don't have extra columns from call deft subs. If that was all this did, we don't need it.
    my @clist = caller(0); 
    my $msg = "Error in gc $clist[3] called from $clist[1] line $clist[2], died";
    write_log("$msg");
    return;
    my $collect = pop(@sub_stack);
    my %unique;
    my @key_list;
    my @clear_list;

    if (! $collect)
    {
	my %urh;
	while(unwind(\%urh))
	{
	    rewind(\%urh);
	}
	return;
    }

    # else...

    my %urh;
    my $first_flag = 1;
    while(unwind(\%urh))
    {
	if ($first_flag)
	{
	    # We don't really care what order, but 
	    # we need to save the keys in a static order

	    my @raw_list = sys_keys_eenv();
	    $first_flag = 0;
	    foreach my $key (@raw_list)
	    {
		if ($key =~ m/^$collect\_/)
		{
		    # List of columns being garbage collected.
		    push(@clear_list, $key);
		}
		else
		{
		    # List of columns we'll keep.
		    push(@key_list, $key);
		}
	    }
	}

	foreach my $key (@clear_list)
	{
	    # Delete columns not current.
	    clear_var_eenv($key);
	}

	# Build a cumulative value key for the current record.
	# If unique then rewind else don't rewind.

	my $cumulative = "\t";
	foreach my $key (@key_list)
	{
	    $cumulative .= get_eenv($key) . "\t";
	}

	my $xx = 0;
	if (! exists($unique{$cumulative}))
	{
	    $unique{$cumulative} = 1;
	    print "rw:$xx\n";
	    $xx++;
	    rewind(\%urh);
	}
    }
}



# Save the current alias list of column names.
# Create a new list for the current scope.

# Note id1:
# If the arg doesn't exist already as an alias, we have an error.
# use the alias of the existing arg. This removes the need 
# to backtrack up the tree looking for an original alias.
# In other words, the original alias must be propogated 
# through every alias_ref.

# Note id2:
# Copy any args into the new alias.
# We cannot overwrite the old (current) alias_ref until the end
# because we have to look up the aliases of all the named protos.

# sub da
# {
#     print "alias_ref: " . Dumper($alias_ref) . "\n";
# }

# inc_scope pushes a new stack frame onto each row stack. The whole ancestor stack is copied so that when it
# is time to rewind the row has all the previous stack frames necessary to resolve the current row against the
# row in the previous stack frame.

# @proto is the prototype of the deft subroutine, in otherwords the subroutine-local names of the sub
# parameters.

# @arg are the args of the call, in otherwords the deft vars in the call.

sub inc_scope 
{
    my @proto = @{$_[0]};
    my @arg = @{$_[1]};

    foreach my $row (@table) # (0..$#{$table[0]})
    {
        # Use hash slice as both lvalue and value.
        my $new_scope;
        @{$new_scope}{@proto} = @{[@{$row->[0]}{@arg}]};
        unshift @{$row}, $new_scope;
    }
}

sub dec_scope
{
    my @proto = @{$_[0]};
    my @arg = @{$_[1]};

    foreach my $row (@table) # (0..$#{$table[0]})
    {
        # Use hash slice as both lvalue and value.
        @{$row->[1]}{@arg} = @{$row->[0]}{@proto};
        shift @{$row};
    }
}


# external name = internal name
# key is user var, value is sys var
# sub push_alias
# {
#     print "p_a user:$_[0] sys:$_[1]\n";
#     $alias_ref->{$_[0]} = $_[1];
# }

# Given a user var, return the sys var.
# sub alias
# {
#     return $alias_ref->{$_[0]};
# }

# sub clear_alias
# {
#     delete($alias_ref->{$_[0]});
# }


# Usage:
# set_eenv("col", value)
# Try to look up the aliased name. If we don't
# find it, we must be initializing (instantiating) a local variable.
# This is a good place to init a local var. We simply need to
# create the var's name. Also see inc_scope() which does a similar
# operation for Deft subroutine args.

sub set_eenv
{
    if (! $eenv)
    {
	# (caller(0))[3] is here. Parent file and line are 1 and 2.
	# die w/o trailing \n prints file and line number after the message. 
	my @clist = caller(0); 
	die "null eenv in set_eenv $clist[3] called from $clist[1] line $clist[2], died";
    }
    # feb 12 2013 commented out because it appears to prevent creating a new column
    # if (! exists($eenv{$_[0]}))
    # {
    #     die "Error: non existing var in set_eenv: $_[0]\n";
    # }
    $eenv->{$_[0]} = $_[1];
}


# Copy all the non-internal cols from one record to another.
# Usage: copy_eenv($orig_ref_eenv, $dest_ref_eenv);
sub copy_eenv
{
    my @clist = caller(0); 
    my $msg = "Error in copy_eenv $clist[3] called from $clist[1] line $clist[2], died";
    die "copy_eenv() called. Should used clone() instead.\n$msg\n";

    foreach my $item (keys(%{$_[0]}))
    {
	# Don't overwrite internal vars. It might be better to use
	# alias somehow instead of doing a regexp against the raw eenv
	# col names.
	if ($item !~ m/^\d+\._/)
	{
	    $_[1]->{$item} = $_[0]->{$item};
	}
    }
}

# What did this do and where was it used?
sub set_all_eenv
{
    die "common_lib.pl set_all_eenv is broken\n";
    foreach my $item (keys(%{$eenv}))
    {
	$eenv->{$item} = $$item;
    }
}


# Usage:
# value = get_eenv("col")
# raw_key() below also gets values directly from %eenv.
sub get_eenv
{
    if (! $eenv)
    {
	# (caller(0))[3] is here. Parent file and line are 1 and 2.
	# die w/o trailing \n prints file and line number after the message. 
	my @clist = caller(0); 
	die "null eenv in get_eenv $clist[3] called from $clist[1] line $clist[2], died";
    }
    if (exists($eenv->{$_[0]}))
    {
	return $eenv->{$_[0]};
    }
    return undef;

    # memoz() is called which calls slice_eenv() before a column is even created in a new row. We need to be
    # able to gracefully slice for non-existent cols.

    # else
    # {
    #     my @clist = caller(0); 
    #     die "don't have col $_[0] $clist[3] called from $clist[1] line $clist[2], died";
    #     return undef;
    # }
}


# Usage:
# value = get_eenv_handle("col",$hashref)
# It isn't a handle, but the word "ref" is already 
# in use. Used by keycmp() in runtlib.pl
sub get_eenv_handle
{
    return $_[1]->{$_[0]};
}



# Usage: for debugging only
# value = d_get_eenv(col)
sub d_get_eenv
{
    return $eenv->{$_[0]};
}

# The keys that the user can see in the local scope.
# Usage:
# @array = user_keys_eenv()
sub user_keys_eenv
{
    # return values(%{$alias_ref});
    return keys(%{$eenv});
}

# The real keys in %eenv for the local scope.
# Usage:
# @array = sys_keys_eenv()
# This must return keys in the same order as raw_key.
sub sys_keys_eenv
{
    # return sort {$a cmp $b} keys(%{$alias_ref});
    return sort {$a cmp $b} keys(%{$eenv});
}


# Newthink: $eenv is a hash ref. Just return it.

# Oldthink: Need a ref to the current eenv, but when we change eenv, we don't
# want what this refers to to change.

# Old Usage:
# %eenv_copy = %{get_ref_eenv()};
sub get_ref_eenv
{
    return $eenv;
    #my %temp = %eenv;
    #return \%temp;
}


# This is is used a LOT so we need it to be efficient.
# I deemed it inefficient to either use get_ref_eenv() and
# it seems dangerous to allow higher level code to have
# a handle to the real eenv (get_ref_eenv() returns a handle to 
# a copy of eenv).

sub freeze_eenv
{
    return freeze($eenv);
}


# Usage: set_ref_eenv(\%eenv_copy)
# set_ref_eenv($table[$rowc][$scope]); where $scope is always zero
# set_ref_eenv($table[$rowc][0]);

# Make the global $eenv a particular record of our choosing, and we
# better choose a eeref from something like popping the stream.

sub set_ref_eenv
{
    if (! defined($_[0]))
    {
	# (caller(0))[3] is here. Parent file and line are 1 and 2.
	# die w/o trailing \n prints file and line number after the message. 
	my @clist = caller(0); 
	die "undef stream in set_ref_eenv $clist[3] called from $clist[1] line $clist[2], died";
    }
    $eenv = $_[0];
    # printf("sre ref: %ld\n", $eenv);
}


# Usage:
# exists_eenv($col)
sub exists_eenv
{
    return exists($eenv->{$_[0]});
}

# Usage:
# @array1  = @{slice_eenv(\@array2)}
sub slice_eenv
{
    my $hr = $eenv;
    my @val = @{$hr}{@_};
    return \@val;
}


# my $view_key = join(' ,', @{slice_eenv(\@view)});
# Don't use clever tweening. We don't care about the extra
# terminal comma. Just don't forget the key is ', ' terminated.
# Usage:
# 
sub slice_key
{
    my $key;
    foreach my $val (@{$_[0]})
    {
	$key .= get_eenv($val) . ', ';
    }
    return $key;
}


# Build a view key for all the cols in the record, 
# not just cols in the local scope.
# This doesn't use clever tweening. We don't care about the extra
# terminal comma. Just don't forget the key is ', ' terminated.
# Usage:
# my $view_key = raw_key();
# This must return keys in the same order as sys_keys_eenv().
sub raw_key
{
    my $key;
    foreach my $val (sort {$a cmp $b} keys(%{$eenv}))
    {
	$key .= $eenv->{$val} . ', ';
    }
    return $key;
}


# Return a hash  (note *hash*, not a list slice) which is
# vars listed in @_ which is 
# an array ref as with slice_eenv() above.
# Usage:
# %new_ref_eenv = local_eenv(\@array);
sub local_eenv
{
    die "local_eenv() not used\n";
    my %temp;
    # @temp{@_} = @eenv{@{$_[0]}};
    foreach my $key (@{$_[0]})
    {
	# $key = alias($key);
	#$temp{$key} = $eenv{$key};
	#$temp{alias($key)} = $eenv{$key};
	$temp{alias($key)} = get_eenv($key);
    }
    return \%temp;
}



# Usage:
# @array1  = @{neg_slice_eenv(\@array2)}
sub neg_slice_eenv
{
    my @temp = @{$_[0]};
    my %temp;
    foreach my $item (@temp)
    {
	$temp{$item} = 1;
    }
    my @keys = sys_keys_eenv;    
    my $hr = $eenv;
    my @val;
    foreach my $key (@keys) 
    {
	if (!(exists($temp{$key})))
	{
	    push @val, $hr->{$key};
	}
    }
    return \@val;
}

# Usage:
# clear_eenv()
# I can't remember why we would want to keep 
# empty cols in %eenv. Just clear out the whole hash.
# Which is faster: new hash or undef old hash?
sub clear_eenv
{
    undef($eenv);
}

# Usage:
# my $scalar_var = scalar_eenv();
# Used to test if %eenv is empty.
sub scalar_eenv
{
    return scalar(%{$eenv});
}

sub clear_var_eenv
{
    delete($eenv->{$_[0]});
}


# Diff two env refs. If the second arg is blank then diff
# against the current eenv.

sub diff_eenv
{
    if (! $_[0])
    {
	die "diff needs at least one argument\n";
    }

    # Empirically reversed from what Noah wrote.

    my $aa = $_[1];
    my $bb = $_[0];
    if (! defined($bb))
    {
	$bb = get_ref_eenv();
    }

    # Is $_ really necessary here? Can't we use a real variable?
    
    my %diff;
    if (0)
    {
	%diff = map { $_ => (exists($aa->{$_}) && $bb->{$_}) } keys(%{$bb});
	%diff = ( %diff, %{$aa} );
    }
    else
    {
	foreach my $key (keys(%{$bb}))
	{
	    # print "diff key:$key bb:$bb->{$key}\n";
	    if (exists($aa->{$key}) && $bb->{$key})
	    {
		$diff{$key} = $bb->{$key};
	    }
	}
	%diff = ( %diff, %{$aa} );
    }

#     foreach my $key (keys(%diff))
#     {
# 	print "i:$::in_stream diff: $key:$diff{$key}\n";
#     }
    return \%diff;
}


# Take the result of a diff and an env ref and return the result
# of the one merged with the other. We need to be able to
# manufacture or destroy rows if that is what is called for.
# The args are a list of patches. If no args then destroy the row.

# Scalar Deft does not use the array aspect of patches as scalar code 
# will always only patch one record at a time. However, this feature
# will be used when all the API code is converted over to using
# record diff/patch.

sub patch_eenv
{
    die "in patch_eenv";
    my $urh = $_[0];

    # out_stream is set in st_lib.pl rewind()
    my $out_stream = $urh->{out_stream};

    my $eenv_ref = get_ref_eenv();

    foreach my $key (sort(keys(%{$eenv_ref})))
    {
	print "pe eenv:$key:$eenv_ref->{$key}\n";
    }

    # $urh->{view_key} is set in st_lib.pl unwind.
    my $view_key = $urh->{view_key};
    foreach my $patch (@{$urh->{$view_key}})
    {
	foreach my $key (sort(keys(%{$patch})))
	{
	    print "pe patch key $key:$patch->{$key}\n";
	}

	my %out_eenv = ( %{$eenv_ref}, %{$patch} );

	foreach my $key (sort(keys(%out_eenv)))
	{
	    print "oe:$key:$out_eenv{$key}\n";
	}

	if (! defined(\%out_eenv))
	{
	    # debug? Real error trap?
	    die "undef out_eenv er:$eenv_ref pa:$patch\n";
	}
	set_ref_eenv(\%out_eenv);
	pe_rewind($urh); # Passed in the output stream
    }
}


# Can't depend on %eenv for values after rewinding has finished
# because unwind clears eenv before it starts. Therefore,
# when there is no record to unwind, %eenv is empty.

my $global_rval = 0;
sub set_return
{
    $global_rval = $eenv->{"_return"};
}

sub get_return
{
    return $global_rval;
}


# Get all the scalars. We need to know if there
# are any new variables created by this line of code.

sub getvars
{
    my $code = $_[0];
    my %var_hash;
    while($code =~ m/(?<!\\)\$([a-zA-Z_][\w\d]*)(?![\[\{])/g)
    {
	$var_hash{$1} = 1;
    }
    return keys(%var_hash);
}

sub a_dot_out
{
    my $stem = $_[0];

    my $fn = "$stem\.pl";
    
    if (-e $fn)
    {
	my $temp = `grep -c \"Created by deft2perl\.pl\" $fn`;
	chomp($temp);
	if ($temp > 0)
	{
	    return $fn;
	}
	else
	{
	    write_log("Warning: $stem\.deft compiling to $stem\.deft\.pl since $stem\.pl is not a Deft output file.\n");
	    return "$stem\.deft\.pl";
	}
    }
    return $fn;
}

my %_d_code_refs;

sub init_ref
{
    # This populates an array of references to code, aka function
    # references. The key is the subroutine name.

    $_d_code_refs{$_[0]} = $_[1];
    # print "key:$_[0] value:$_[1]\n";
}

sub new_dispatch
{
    &{$_d_code_refs{"stuff"}};
}

sub dispatch
{
    die "don't use this\n";
    my $var = $_[0];

    my %urh;
    while(unwind(\%urh))
    {
	my $sub_name = get_eenv($var);

	# Noah really wants to restrict this regex to things
	# that are valid subroutine calls.
	
	$sub_name =~ s/&?([\w\d]+)(?:\(\))?/$1/;
	if (exists($_d_code_refs{$sub_name}))
	{
	    &{$_d_code_refs{$sub_name}};
	}
	else
	{
	    write_log("Error: dispatch, no Deft sub $sub_name \"$_d_code_refs{$sub_name}\"");
	    my $out = "Error: dispatch, var:$_[0] has no Deft sub:$sub_name \"$_d_code_refs{$sub_name}\"\n";
	    foreach my $key (keys(%_d_code_refs))
	    {
		$out .= "$key\n";
	    }
	    die "$out\n";
	}
	rewind(\%urh);
    }
}


# Add shebang, initial "require" statements and creator comment.
# Goes before main:

sub gen_shebang
{
    my $output .=   "#!/usr/bin/perl
# Created by deft2perl.pl
# Do not edit this file.
# FindBin add this script's path to \@INC
# and it even allows \"use\" to work on symlinked modules.
use FindBin;
use lib \$FindBin::Bin;
BEGIN
{
\$::_d_path = \"$::_d_path\";
}
use lib \$::_d_path;
use session_lib;
require \"$::_d_path/sql_lib.pl\";
require \"$::_d_path/st_lib.pl\";
require \"$::_d_path/stll_lib.pl\";
require \"$::_d_path/dcslib.pl\";
require \"$::_d_path/runtlib.pl\";
require \"$::_d_path/runt.pl\";
require \"$::_d_path/common_lib.pl\";
require \"$::_d_path/runt_compile.pl\";
# my \%_d_code_refs;
";

    # Create a hash code references of the user defined Deft subroutines
    # for use by the call_deft feature. 
    foreach my $dsub (keys(%is_dsub))
    {
	# (my $fixed_dsub) = $dsub =~ m/(.*)\(\)$/;

    	#$output .= "\$_d_code_refs{$dsub} = \\\&$dsub;\n";

	# New code inits a hash in common_lib.pl via a function.
	# Probably even better to use a closure.
	$output .= "init_ref(\"$dsub\", \\\&$dsub);\n";
    }


$output .= '# sub dispatch moved to common_lib.pl';
    return $output;    
}


# feb 18 2007
# This code is back more or less to the original. Var names are unchanged
# in the code and all column names are looked up via alias() which is a
# scope-specific alias hash.
# Noah initially called these "populate" and 
# "gather" in st_lib.pl:unwind_full(), but I'll rename them in keeping
# with historical usage of get and set.

sub gen_varlist
{
    my $expression = $_[0];
    my $curr_sub = $_[1];

    my @varlist = getvars($expression);

    my $get_local = "";
    my $set_local = "";
    my $view_list = "";
    my $loc_tween = "";
    my $vl_tween = "";

    foreach my $var (@varlist)
    {
	$get_local .= $loc_tween . "my \$$var = get_eenv(\"$var\");";
	$set_local .= $loc_tween . "set_eenv(\"$var\", \$$var);";
	$loc_tween = "\n";
	$view_list .= "$vl_tween\"$var\"";
	$vl_tween = ", ";
    }
    return ($get_local, $set_local, $view_list);
}


# A string cannot be a token if it contains an opening 
# but not a closing escaped region.

sub is_token
{
    my ($token,$comment) = @_;
    if (0)
    {
	if ($token !~ m/(?<!\\)(?:[\'\"\`]|m\/|s\/|tr\/|qw\/|qr\/)/)
	{
	    return 1;
	}
	elsif ($token =~ s/(?:s|tr)\/.*?(?<!\\)\/.*?(?<!\\)\///s || 
	       $token =~ s/(?<!\\)([\/\'\"\`]).*?(?<!\\)\1//s)
	{
	    return (is_token($token));
	}
	else
	{
	    return 0;
	}
    }
    else
    {
	if ($comment eq '#')
	{
	    # This is a comment. Tokenizing comments is useless (and very, very expensive).
	    return 1;
	}
	if ($token !~ m/(?<!\\)(?:\\\\)*(?:[\'\"\`]|m\/|s\/|tr\/|qw\/|qr\/)/)
	{
	    return 1;
	}
	elsif ($token =~ s/(?:s|tr)\/.*?(?<!\\)(?:\\\\)*\/.*?(?<!\\)(?:\\\\)*\///s || 
	       $token =~ s/(?<!\\)(\\\\)*([\/\'\"\`]).*?(?<!\\)(?:\\\\)*\2/$1/s)
	{
	    return (is_token($token));
	}
	else
	{
	    return 0;
	}
    }
}

# In case we haven't mentioned it regexes must be m/ s/ tr/.
# Bare // are not allowed. Ha!

# Note 5.
# If the last (previous) token was # we must be in a comment.
# This is essentially a trivial look-behind, which is no surprise
# in a tokenizer.

sub tokenize
{
    my $all = $_[0];
    my $token = "";
    my @out = ("\n");

    my $line_count = 0;
    while ($all) 
    {
	my $try = "";

	# Match characters that can be tokens. Next we'll test
	# to see if we have a token. If we have a token, do some special
	# processing with # and \n. If not a token, keep matching.

	if ($all =~ s/^((?:[\{\}\;\n\#])|(?:.*?(?=[\{\;\}\n\#])))//)
	{
	    if ($1 eq "\n")
	    {
		$line_count++;		
	    }
	    $try = "$token$1";

	    # See note 5 above. 

	    if (is_token($try,$out[$#out]))
	    {
		if ($out[$#out] ne '#') 
		{
		    push @out, $try;
		}
		elsif ($try eq "\n")
		{
		    pop @out;
		}
		$token = '';
	    }
	    else
	    {
		$token .= $1;
	    }
	}
	elsif ($all =~ m/^\s+$/)
	{
	    $all = '';
	}
	else
	{
	    print "Failed on $line_count near: $token\n";
	    exit();
	}
    }    

    # Use an accumulator string. 
    # If we get to something that could be the end of the line
    # and the accumulator has contents, push it.
    # Often we get to an apparent end of line with an empty accumulator.

    my @final;
    my $accumulate = "";
    foreach my $item (@out)
    {
	$item =~ s/^\s*(.*?)\s*$/$1/sg;
	if ($item)
	{
	    if ($item !~ m/^[\{\}\;]$/)
	    {
		$accumulate .= $item;
	    }
	    else
	    {
		if ($accumulate)
		{
		    push(@final, $accumulate);
		    $accumulate = "";
		}
		push(@final, $item);
	    }
	}
    }
    return @final;
}



# We might be asked for the next_valid() of the last line.
# In this special case, we return undef.

sub next_valid
{
    my $code_ref = $_[0];
    my $start_index = $_[1];

    $start_index++;
    for(my $xx = $start_index; $xx <= $#{$code_ref}; $xx++)
    {
	if ($code_ref->[$xx][1] != $wrap_delete)
	{
	    return $code_ref->[$xx][1];
	}
    }
    return undef;
}


# Populate $code_ref->[2] with the name of the enclosing
# subroutine.

sub mark_enclosing
{
    my $code_ref = $_[0];

    my $curr_sub = "";
    my $p_flag = 0;
    my $max = $#{$code_ref};
    for(my $xx = 0; $xx <= $max; $xx++)
    {
	my $code = $code_ref->[$xx][0];
	if ($code =~ m/^main:/)
	{
	    $curr_sub = "main";
	    $p_flag = 0;
	}
	elsif ($code =~ m/^sub\s+(.*)/)
	{
	    $curr_sub = $1;
	    $p_flag = 0;
	}
	elsif ($code =~ m/^perl\s+(.*)/)
	{
	    $curr_sub = $1;
	    $p_flag = 1;
	}
	# print "old2:$code_ref->[$xx][2] xx:$xx new2:$curr_sub\n";
	$code_ref->[$xx][2] = $curr_sub;
    }
}

# Renamed old var to $mp_scope. Might need fixing.
sub mark_perl
{
    my $code_ref = $_[0];

    my $max = $#{$code_ref};
    my $pflag = 0;
    my $mp_scope = 0; # mnemonic: mark perl scope
    for(my $xx = 0; $xx <= $max; $xx++)
    {
	# This could be changed to a type check on [1].
	if (! $pflag)
	{
	    if ($code_ref->[$xx][1] == $wrap_perl)
	    {
		# Not /g only change first instance
		$code_ref->[$xx][0] =~ s/perl\s+/sub /; 
		$pflag = 1;
	    }
	}
	else
	{
	    if ($code_ref->[$xx][0] eq '{')
	    {
		$mp_scope++;
	    }
	    elsif ($code_ref->[$xx][0] eq '}')
	    {
		$mp_scope--;
	    }
 	    if ($mp_scope == 0)
 	    {
 		$pflag = 0;
 	    }
 	    elsif ($code_ref->[$xx][1] != $wrap_delete)  
 	    {
 		$code_ref->[$xx][1] = $wrap_none;   
 		if ($xx < $max && $code_ref->[$xx+1][0] eq ";")
 		{
 		    $code_ref->[$xx][0] .= ";";
 		}
 	    }
	}
    }
}


# Set the wrap type for subroutine calls. 
# Change args to strings

sub mark_sub_calls
{
    my $code_ref = $_[0];

    # The last line of code_ref can't be a statment
    # because statements have a following line with a ";"
    # Stop the loop at $xx < max.

    # The current "line" is $code in keeping with the convention 
    # in the other subroutines here. The "next line" is $next_line.

    for(my $xx = 0; $xx < $#{$code_ref}; $xx++)
    {
	my $code = $code_ref->[$xx][0];
	my $next_line = $code_ref->[$xx+1][0];

	if ($next_line eq ';')
	{
	    if ($code =~ m/(^\&[a-za-z0-9_]+|^[a-za-z0-9_]+\()/)
	    {
		my $sub_name = "$1";
		$sub_name =~ s/.*?(\w+).*/$1/s;
		if (exists($deft_func{$sub_name}))
		{
		    $code_ref->[$xx][1] = $wrap_top;
		}
		elsif (exists($is_dsub{$sub_name}))
		{
		    $code_ref->[$xx][1] = $wrap_dsub;
		}


		# In dsub calls, change $var to "$var". 
		# This seem far too complex for such a simple process.
		# Why not just an s regex?
		# There was some (bad) code in the else clause
		# that used to change $var to $_[0] (the old local_cols())
		
		# Must not change vars where the $ is escaped as \$
		# Pulled some code from Noah's regex in genvars() above.

		if (1)
		{
		    $code_ref->[$xx][0] =~ s/(?<!\\)\$([A-Za-z0-9_]+)/\"$1\"/g;
		}
		else
		{
		    my %vars;
		    while ($code_ref->[$xx][0] =~ m/\$([A-Za-z0-9_]+)/g)
		    {
			$vars{$1} = 1;
		    }
		    
		    foreach my $orig_var (keys(%vars))
		    {
			my $new_var = "\"$orig_var\"";
			$code_ref->[$xx][0] =~ s/\$$orig_var/$new_var/g;
		    }
		}
	    }
	}
    }
}

sub mark_stream
{
    my $code_ref = $_[0];
    my @out;
    my $stream_counter = 0;
    foreach my $element (@{$code_ref})
    {
        push(@out, $element);
        if ($element->[1] == $wrap_scalar)
        {
            $stream_counter++;
            my @list = ("# stream_counter: $stream_counter", $wrap_comment, $element->[2]);
            push(@out, \@list);
        }
    }
    @{$code_ref} = @out;
}


# After calling mark_if() these things will be true:
# - The start of an if w/o an else is "if".
# - The start of an if with an else is "if_else".
# - The start of the true block is always if_start (but may be changed later).
# - The end of an entire if statement is if_stop 
# - The end of the true part of an if-else is if_welse_stop.
# - The end of an else is else_stop.

# Dec 22 2013 rename old var to $if_scope
sub mark_if
{
    my $code_ref = $_[0];
    my $if_scope = 0;
    my %if_hash;
    my %stop_hash;

    my $max = $#{$code_ref};
    for(my $xx = 0; $xx <= $max; $xx++)
    {
	# debug
	#$code_ref->[$xx][0] = "# xx:$xx d:$if_scope\n$code_ref->[$xx][0]";

	# This could be changed to a type check on [1].
 	if ($code_ref->[$xx][1] == $wrap_if_start ||
	    $code_ref->[$xx][1] == $wrap_else_start)
 	{
 	    $if_scope++;
	    # debug
	    #$code_ref->[$xx][0] = "# start d:$if_scope\n$code_ref->[$xx][0]";
 	}
	
	# Decrement if_scope at any stop, if_stop or else_stop.
	# Old-think: only dec for if_stop.
	
	if ($code_ref->[$xx][1] == $wrap_if_stop ||
	    $code_ref->[$xx][1] == $wrap_else_stop)
	{
	    $if_scope--;
	    $stop_hash{$if_scope} = $xx;
	    # debug
	    #$code_ref->[$xx][0] .= " # d:$if_scope xx:$xx";
	}
	elsif ($code_ref->[$xx][1] == $wrap_if)
	{
	    # debug
	    # $code_ref->[$xx][0] .= " # set ih $if_scope to $xx ";
	    $if_hash{$if_scope} = $xx; # do exists check here
	}
	elsif ($code_ref->[$xx][1] == $wrap_elsif )
	{
	    # change our ancestor
	    if (exists($if_hash{$if_scope}))
	    {
		if ($code_ref->[$if_hash{$if_scope}][1] == $wrap_if)
		{
		    $code_ref->[$if_hash{$if_scope}][1] = $wrap_if_else;
		}
		elsif ($code_ref->[$if_hash{$if_scope}][1] == $wrap_elsif)
		{
		    $code_ref->[$if_hash{$if_scope}][1] = $wrap_elsif_else;
		}
		delete($if_hash{$if_scope});
	    }
	    # get ready for any descendents
	    $if_hash{$if_scope} = $xx; # do exists check here
	}
	elsif ($code_ref->[$xx][1] == $wrap_else)
	{
	    # debug
	    #$code_ref->[$xx][0] .= " # else-scope:$if_scope sh:$stop_hash{$if_scope} ih:$if_hash{$if_scope}";
	    if (exists($if_hash{$if_scope}))
	    {
		if ($code_ref->[$if_hash{$if_scope}][1] == $wrap_if)
		{
		    $code_ref->[$if_hash{$if_scope}][1] = $wrap_if_else;
		}
		elsif ($code_ref->[$if_hash{$if_scope}][1] == $wrap_elsif)
		{
		    $code_ref->[$if_hash{$if_scope}][1] = $wrap_elsif_else;
		}
		delete($if_hash{$if_scope});

		if ($code_ref->[$stop_hash{$if_scope}][1] == $wrap_if_stop)
		{
		    $code_ref->[$stop_hash{$if_scope}][1] = $wrap_if_welse_stop;
		    # debug
		    #$code_ref->[$stop_hash{$if_scope}][0] .= " # changed to wrap_if_welse_stop";
		}
		delete($stop_hash{$if_scope});
	    }
	}
	
	# If_Scope zero if_hash is overwritten by the next "if",
	# if there was no else. At one point we cleaned up the if_hash
	# here (at this line), but that was a bug.
    }
}


# Change the start which is the next line, into 
# the proper starting type. 
# This seems to change if_start to if_welse_start as appropriate.

sub mark_starts
{
    my $code_ref = $_[0];

    for(my $xx = 0; $xx < $#{$code_ref}; $xx++)
    {
	if ($start_type[$code_ref->[$xx][1]])
	{
	    $code_ref->[$xx+1][1] = $start_type[$code_ref->[$xx][1]];
	}
    }
}


# Add tokens to the code. Every if needs a surrounding
# block to handle the stream joins.
# Always copy all 3 elements of a code_ref entry!
# Better to use a function to do this, so the function
# could sanity check the assignment.

# Read the @code, push everything into a new copy.
# push additional lines for the union_stream calls.
# Matching pairs are: if_start and if_stop, if_else and if_stop.

# Each needs different stream unioning behavior, 
# We can use $xx to check the type of the original line.

sub add_unions
{
    my $code_ref = $_[0];

    my @dest_code;
    my @if_tracker;
    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
 	if ($code_ref->[$xx][1] == $wrap_if_start ||
 	    $code_ref->[$xx][1] == $wrap_if_welse_start)
 	{
 	    push(@if_tracker, $xx);
 	    push(@dest_code, ["{", $wrap_union_start, $code_ref->[$xx][2]]);
 	}

	# Copy line of code to dest
	push(@dest_code, [$code_ref->[$xx][0], $code_ref->[$xx][1], $code_ref->[$xx][2]]);

	if (($code_ref->[$xx][1] == $wrap_if_stop &&
	    $code_ref->[$xx+1][1] != $wrap_else) ||
	    $code_ref->[$xx][1] == $wrap_else_stop)
	{
	    pop(@if_tracker);
	    push(@dest_code, ["}", $wrap_union_stop, $code_ref->[$xx][2]]);
	}
    }

    for(my $xx = 0; $xx <= $#dest_code; $xx++)
    {
	$code_ref->[$xx] = $dest_code[$xx];
    }
}

# Use %% as % since this is a printf format string.

my $if_fmt = '{
set_view_list(%s);
memoz();
treset(); # 
while( unwind())
{
# get local (get cols)
%s
# if expression
if (%s)
{
$::out_stream = read_stack(0);
}
else
{
$::out_stream = read_stack(1);
}
# set local (set cols)
%s
rewind();
}
}';

# if, if_else 
# Not currently supported: elsif, elsif_else

sub gen_if
{
    my $code_ref = $_[0];

    # start at zero, end one short because we check $xx+1.

    for(my $xx = 0; $xx < $#{$code_ref}; $xx++)
    {
	my $code = $code_ref->[$xx][0];
	my $type = $code_ref->[$xx][1];
	my $curr_sub = $code_ref->[$xx][2];
	
	if ($type == $wrap_if ||
	    $type == $wrap_elsif || 
	    $type == $wrap_if_else ||
	    $type == $wrap_elsif_else)
	{
	    my $if_expression;
	    # Was non-greedy. Fixed? 
	    if ($code =~ m/if\s*\((.*)\)/) # \s*(\{.*\})/s)
	    {
		$if_expression = $1;
	    }
	    (my $get_local,
	     my $set_local,
	     my $view_list) = gen_varlist($if_expression, $curr_sub);
	    
	    my $gen_cond = ""; # "{\n";
	    
	    $gen_cond .= sprintf($if_fmt,
				 $view_list,
				 $get_local,
				 $if_expression,
				 $set_local);
	    
	    $code_ref->[$xx][0] = $gen_cond;
	}
	# else do nothing. We (the code?) already have a closing curly brace.
    }
}

my $agg_fmt = '
# ags_start
my %%urh;
$urh{view_list} = [%s];
my %%unique;
my $pop_count = 0;
my @key_list = %s; # $key_code;
$::in_stream = pop_stack();
while(unwind(\%%urh))
 {
  $key = slice_key(\@key_list);
  if (! exists($unique{$key}))
  {
    $unique{$key} = next_stack();
    $pop_count++;
  }
  $::out_stream = $unique{$key};
  rewind(\%%urh);
 }
';

my $ags_start = 'while($pop_count >= 0)
{ # ags calling loop
$pop_count--;
';

my $ags_stop = 'push_multi();
} # ags_stop
join_multi();
';

# From what I can tell by reading the Perl output from the compiler in content_manager/index.pl,
# agg_simple(page_pk) will run the code block once for each unique value in page_pk. This might be viewed as a
# sloppy shortcut to providing a unique key based on data, but it is easier. Or not. It is like doing a SQL
# select distinct(), for example: select distinct(page_pk) from all_pages;

sub gen_agg
{
    my $code_ref = $_[0];
    # start at zero, end one short because we check $xx+1.

    for(my $xx = 0; $xx < $#{$code_ref}; $xx++)
    {
	my $code = $code_ref->[$xx][0];
	my $type = $code_ref->[$xx][1];
	
	if ($type == $wrap_ags)
	{
	    $code =~ s/.*\"(.*)\".*/$1/;
	    my @key_list = split(/,/ , $code);
	    my $key_code = "(";
	    my $tween = "";
	    foreach my $item (@key_list)
	    {
		$key_code .= "$tween\"$item\"";
		$tween = ",";
	    }
	    $key_code .= ")";

	    my $view_list = "fix code in common_lib gen_agg";
	    
	    my $gen_cond .= sprintf($agg_fmt, $view_list, $key_code);
	    $code_ref->[$xx][0] = $gen_cond;
	}
	elsif ($type == $wrap_ags_start)
	{
	    $code_ref->[$xx][0] = $ags_start;
	}
	elsif ($type == $wrap_ags_stop)
	{
	    $code_ref->[$xx][0] = $ags_stop;
	}
    }
}


# printf format string for gen_scalar.
# Note use of single ticks instead of typical double quotes.
# Note anonymous block; surrounding left curly and right curly.

my $gs_fmt = '{
set_view_list(%s);
memoz();
treset();
while ( unwind())
{
# get cols
%s
# code
%s
# set cols
%s
rewind();
}
}';

# Combine scalar lines, then wrap.
# We have given up on the (bad) idea of stream_ok.
# There may still be some anonymous blocks created in the compiled code.

sub gen_scalar
{
    my $code_ref = $_[0];
    my $s_flag = 0; # true while we have multiple scalar lines
    my $code_str = "";
    my $last_scalar_line = -1;
    my $code_tween = "";

    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
	my $code = $code_ref->[$xx][0];
	my $type = $code_ref->[$xx][1];
	my $curr_sub = $code_ref->[$xx][2];
	
        if ($type == $wrap_comment)
        {
            $code_str .= "$code\n";
        }

	if ($type == $wrap_none ||
	    $type == $wrap_delete)
	{
	    next; # skip non-wrapped lines
	}

	# This needs a comment. Maybe a whole paragraph

	if ($type == $wrap_scalar)
	{
	    if ($s_flag == 0)
	    {
		$s_flag = 1;
	    }
	    $code_str .= "$code_tween$code;"; # another assignment below
	    $code_tween = "\n";               # another assignment below
	    $code_ref->[$xx][0] = "";
	    $code_ref->[$xx][1] = $wrap_delete;
	    $last_scalar_line = $xx;
	} 
	elsif ($s_flag == 1 && $type != $wrap_scalar)
	{
	    $s_flag = 0;
	    (my $get_local,
	     my $set_local,
	     my $view_list) = gen_varlist($code_str, $curr_sub);

	    $code_ref->[$last_scalar_line][0]
		= sprintf($gs_fmt,
			  $view_list,
			  $get_local,
			  $code_str,
			  $set_local);
	    $code_ref->[$last_scalar_line][1] = $wrap_scalar;
	    $code_str = "";
	    $code_tween = "";
	}
    }
}


# sc = stream code memnonic
my $sc = 'reset_stream();
';

# was skip_stream, then had stream_ok and a left curly.
# Now note left curly.
my $sc_ok = '# sc_ok stream code (was) stream ok
# { this is bad. Should come from if_start
';

# additional code for stream "if", follows normal sc or sc_ok
my $sc_if = '';

# end of split. applies to end of true or false stream split
my $eo_split = '# eo_split
';

# end of union (split) = the end of any group of split streams, when they are all unioned.
my $eo_union = '# eo_union
';

# Gen the stream code.
# @streams is list of lists of hash references
# $stream[x] is a list of the records (hash refs) in stream x.

sub gen_stream_code
{
    my $code_ref = $_[0];

    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
	# handle left curly here
	if ($code_ref->[$xx][1] == $wrap_scalar)
	{
	    if (($xx > 0) &&
		($code_ref->[$xx-1][1] == $wrap_if_start ||
		 $code_ref->[$xx-1][1] == $wrap_if_welse_start ||
		 $code_ref->[$xx-1][1] == $wrap_else_start))
	    {
		$code_ref->[$xx][0] = "$sc_ok$code_ref->[$xx][0]";
	    }
	    else
	    {
		$code_ref->[$xx][0] = "$sc$code_ref->[$xx][0]";
	    }
	    # No semicolon after scalars. Scalars are inside a while block.
	}
	if ($code_ref->[$xx][1] == $wrap_sub ||
	    $code_ref->[$xx][1] == $wrap_dsub )
	{
	    $code_ref->[$xx][0] .= ";";
	}
	elsif ($code_ref->[$xx][1] == $wrap_union_start)
	{
	    $code_ref->[$xx][0] = "new_union();";
	}
	elsif ($code_ref->[$xx][1] == $wrap_top)
	{
	    $code_ref->[$xx][0] = "$sc$code_ref->[$xx][0]";
	    $code_ref->[$xx][0] .= ";";
	}
	elsif ($code_ref->[$xx][1] == $wrap_if ||
	       $code_ref->[$xx][1] == $wrap_if_else ||
	       $code_ref->[$xx][1] == $wrap_elsif)
	{
	    # We have some type of if statement.
	    # Determine if we are the start of a stream split.

 	    if (($xx > 0) &&
 		($code_ref->[$xx-1][1] == $wrap_if_start ||
 		 $code_ref->[$xx-1][1] == $wrap_if_welse_start ||
 		 $code_ref->[$xx-1][1] == $wrap_else_start))
 	    {
		# If the previous line is some kind of start, then 
		# we need to do an if stream_ok check.  

 		$code_ref->[$xx][0] = "$sc_ok$sc_if$code_ref->[$xx][0]";
 	    }
 	    else
	    {
		# The previous line is not a start, therefore we are not
		# the first line of a stream_ok block, so just wrap as normal

		$code_ref->[$xx][0] = "$sc$sc_if$code_ref->[$xx][0]";
	    }
	}
	elsif ($code_ref->[$xx][1] == $wrap_if_stop)
	{
	    # This is the end of the true clause of an if which has no else.
	    # pop_to_union since this split is complete.
	    # Do not union on if_stop because for all we know, there are other splits 
	    # still active. Only union at union_stop.

	    $code_ref->[$xx][0] = "$eo_split$code_ref->[$xx][0] # soline:$xx"; 

	    # Uncomment to Delete right curly by over writing code ref zero.
	    # $code_ref->[$xx][0] = "$eo_split# soline:$xx"; 
	}
	elsif ($code_ref->[$xx][1] == $wrap_if_welse_stop)
	{
	    # A type of end-of-true !!!!!
	    # if_welse_stop only does the end-of-true. The else will add end-of-false.
	    # This is the end if the true clause of an if which also has an else (false) clause.

	    # pop stack to union stack since this is end-of-true.
	    # The name means "wrap if-which-has-a-later-else stop". Bad name.

	    $code_ref->[$xx][0] = "$eo_split$code_ref->[$xx][0]";
	    # Uncomment to Delete the right curly by over writing code ref of zero.
	    # $code_ref->[$xx][0] = "# wrap_if_welse_stop\n$eo_split";
	}
	elsif ($code_ref->[$xx][1] == $wrap_else_stop)
	{
	    # Only uses End-of-False.
	    # This is the end of any else clause.

	    # Do not pop the else stream to the union stack. Simply union the true which is on
	    # the union stack with the current stack which is the false.
	    
	    $code_ref->[$xx][0] = "# wrap_else_stop (aka false) line $xx\n$code_ref->[$xx][0]";

	    # Uncomment to Delete the right curly by over writing code ref of zero.
	    # $code_ref->[$xx][0] = "# wrap_else_stop (aka false) line $xx";
	}
	elsif ($code_ref->[$xx][1] == $wrap_union_stop)
	{
	    $code_ref->[$xx][0] = "$eo_union # eoline line $xx";
	}
    }

    # gsc_pass_2 was a really bad idea (it marked if_start,
    # if_welse_start and else_start for delete). These if clauses
    # really need to be anonymous blocks, and the start of the block
    # really needs to be if_start. These are matched by right curly
    # somewhere else (probably if-stop and if-welse-stop or
    # union_streams()).

    #dump_code($code_ref, 1);
}



# Old(?) Returns a string with a leading comma
# , $_[0], "bar", $_[1], "baz"
# $args{$curr_sub} is a has reference.
# See arg_list() and compile_deft().

# Since inc_scope() and dec_scope() want two lists, return two lists as Perl source in a string.

sub id_args
{
    my $curr_sub = $_[0];
    my $id_args = "";
    my $tween = "";
    my $proto = '[';
    my $arg = '[';
    if (exists($args{$curr_sub}))
    {
	my $proto_ref = $args{$curr_sub};
	# foreach my $key (keys(%{$proto_ref}))
	# {
	#     $id_args .= $tween . ' $_[' . $proto_ref->{$key} . '], "' . $key . '"';
	#     $tween = ",";
	# }
	foreach my $key (keys(%{$proto_ref}))
	{
         $proto .= $tween . '"' . $key . '"';   
         $arg .= $tween . '$_[' . $proto_ref->{$key} . ']';
         # $id_args .= $tween . ' $_[' . $proto_ref->{$key} . '], "' . $key . '"';
	    $tween = ",";
	}
    }
    $proto .= ']';
    $arg .= ']';
    return "$proto, $arg";
}


# Only the starting { of user written Deft subroutines.

sub gen_start_stop
{
    my $code_ref = $_[0];
    my @arg_stack;
    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
	# print "cr2top:$code_ref->[$xx][2]\n";
	if ($code_ref->[$xx][1] == $wrap_sub_start)
	{
	    # $id_args has a leading comma (Huh?)
	    my $id_args = id_args($code_ref->[$xx][2]);
            push(@arg_stack, $id_args);
	    # print "cr2:$code_ref->[$xx][2] ida:$id_args\n";
	    $code_ref->[$xx][0] .= "\ninc_scope($id_args);";
	}
	
	if ($code_ref->[$xx][1] == $wrap_sub_stop)
	{
            my $id_args = pop(@arg_stack);
	    $code_ref->[$xx][0] = "dec_scope($id_args);\n$code_ref->[$xx][0]";
	}
    }
}

sub gen_dsub
{
    my $code_ref = $_[0];
    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
	if ($code_ref->[$xx][1] == $wrap_dsub)
	{
	    $code_ref->[$xx][0] .= "\n$sc" . "garbage_collection();";
	}
    }
}

sub gen_main
{
    my $code_ref = $_[0];
    for(my $xx = 0; $xx <= $#{$code_ref}; $xx++)
    {
	if ($code_ref->[$xx][1] == $wrap_main_start)
	{
	    $code_ref->[$xx][0] .= '
insert_rec();';
	}
    }
}


# Q: What is arg_list doing? A: We keep this so we can generate code
# later to deal with columns that are "passed" to user-written Deft
# subs. Oldthink: We no longer want $curr_sub\_var, so comment that
# out.  We may not want arg_list at all.  Future think: The whole args
# system is crap. There has got to be a better way.

sub arg_list
{
    my $curr_sub = $_[0];
    my $str = $_[1];
    my %proto;
    my $xx = 0;
    while( $str =~ s/\$([A-Za-z0-9_]+)[,]*//)
    {
	# print "cs:$curr_sub arg:$1 xx:$xx\n";
	$proto{"$1"} = $xx;
	$xx++;
    }
    return %proto;
}

sub compile_deft
{
    my $all_lines_ref = $_[0];

    my @code;

    push(@code, [undef, $wrap_none]);

    my @block_stack; # values are wrap types.

    for(my $xx = 0; $xx <= $#{$all_lines_ref}; $xx++)
    {
	my $line = $all_lines_ref->[$xx];
	my $next_line = $all_lines_ref->[$xx+1];

	if ($line =~ m/^perl/)
	{
	    # This needs work...
	    # $key = i_after(\%code, $key, "sub $s_name\n{\n $s_code\n}\n", $wrap_perl);
	    push(@code, ["$line", $wrap_perl]);
	}
	elsif ($line =~ m/^dispatch/)
	{
	    push(@code, [$line, $wrap_dsub]);
	}
	elsif ($line =~ m/^sub\s+([A-Za-z0-9_]+)\s*\((.*)\)/)
	{
	    # sub call with proto arg list
	    my $dsub_name = $1;
	    $is_dsub{$dsub_name} = 1;

	    $line =~ s/\s*\((.*)\)//; # Remove the proto
	    my $proto = $1;

	    # Capture the arg list 
	    %{$args{$dsub_name}} = arg_list($dsub_name, $proto); 

	    # Fix arg list? (What does this comment mean?)
	    # Put the sub name into [2] for later use.
	    push(@code, [$line, $wrap_none, $dsub_name]);
	    push(@block_stack, $wrap_sub);
	}
	elsif ($line =~ m/^sub\s+([A-Za-z0-9_]+)/)
	{
	    $is_dsub{$1} = 1;
	    push(@code, [$line, $wrap_none]);
	    push(@block_stack, $wrap_sub);
	}
	elsif ($line =~ m/^$main_str/)
	{
	    push(@code, [$line, $wrap_main]);
	    push(@block_stack, $wrap_main);
	}
	elsif ($line =~ m/^if_simple/)
	{
	    print "Error:if_simple not supported. ($xx)\n$line\n";
	    exit(1);
	}
	elsif ($line =~ m/^if/)
	{
	    push(@code, [$line, $wrap_if]);
	    push(@block_stack, $wrap_if);
	    # test
	    # push(@code, ["{", $wrap_union_start]);
	}
	elsif ($line =~ m/^else/)
	{
	    push(@code, [$line, $wrap_else]);
	    push(@block_stack, $wrap_else);
	}
	elsif ($line =~ m/^elsif/)
	{
	    print "Error: elsif not supported. Use separate else containg an if\n";
	    print "$line:$xx\n$all_lines_ref->[$xx]\n";
	    exit(1);
	    #push(@code, [$line, $wrap_elsif]);
	    #push(@block_stack, $wrap_elsif);
	}
	elsif ($line =~ m/^agg_simple/)
	{
	    push(@code, [$line, $wrap_ags]);
	    push(@block_stack, $wrap_ags);
	}
	elsif ($line eq "}")
	{
	    # Needs a sanity check.
	    my $type = pop(@block_stack);
	    $type = $end_type[$type];
	    push(@code, [$line, $type]);
	    # test
# 	    if ($type == $wrap_if_stop ||
# 		$type == $wrap_else_stop)
# 	    {
# 		push(@code, [$line, $wrap_union_stop]);
# 	    }
	}
	elsif ($line eq "{")
	{
	    # Needs a sanity check.
	    my $type = $block_stack[$#block_stack];
	    $type = $start_type[$type];
	    push(@code, [$line, $type]);
	}
	elsif ($line eq ";")
	{
	    # This may only apply to ends of main and subs
	    push(@code, [$line, $wrap_delete]);
	}
	else
	{
	    push(@code, [$line, $wrap_scalar]);
	}
	
    }

#      foreach my $key (keys(%args))
#      {
#  	my $hr = $args{$key};
#  	print "k:$key\n";
#  	foreach my $hkey (keys(%{$hr}))
#  	{
#  	    print "$hkey: $hr->{$hkey}\n";
#  	}
#     }

    #dump_code(\@code, 1);

    mark_enclosing(\@code); # and change $str to $sub_str
    #dump_code(\@code, 1);

    mark_perl(\@code);
    #dump_code(\@code, 1);

    mark_sub_calls(\@code); # and change $str to "str", and $str to $_[0]?
    #dump_code(\@code, 1);

    mark_if(\@code);
    # dump_code(\@code, 1);
    
    mark_starts(\@code);
    #dump_code(\@code, 1);

    add_unions(\@code);
    #dump_code(\@code, 1);

    # Used to add comments, or at least to demonstrate the idiom of adding comments.
    mark_stream(\@code);
    # dump_code(\@code, 1);

    gen_if(\@code);
    # dump_code(\@code, 1);

    gen_agg(\@code);
    #dump_code(\@code, 1);

    # combine scalar lines, wrap with while unwind; haven't added stream code yet.
    gen_scalar(\@code);
    # dump_code(\@code, 1);

    # add in stream code. wrap each block with pop_stack, next_stack, pop_to_union
    gen_stream_code(\@code);
    #dump_code(\@code, 1);

    # stream code for start of Deft subs.
    gen_start_stop(\@code);
    #dump_code(\@code, 1);

    gen_dsub(\@code);

    # stream code, etc. for main().
    gen_main(\@code);
    # dump_code(\@code, 1);
    
    return dump_code(\@code, 2);
}

sub dump_code
{
    my $cref = $_[0];

    my $max = 0;
    foreach my $str (@w2t)
    {
	if (length($str) > $max)
	{
	    $max = length($str);
	}
    }

    my $output; 
    foreach my $line_ref (@{$cref})
    {
	# dump code in order for the final compiled Perl version.
	if ($_[1] == 2)
	{
	    if ($line_ref->[1] != $wrap_delete &&
		$line_ref->[1] != $wrap_else)
	    {
		$output .= "$line_ref->[0]\n";
	    }
	    else
	    {
		# Enable this to show deleted code as comments.
		# (show/hide deleted lines of code)
		if (0)
		{
		    $line_ref->[0] =~ s/\n(.*?)/\n# $1/g;
		    $output .= "# deleted:$line_ref->[0]\n";
		}
	    }
	}
	else
	{
	    # Swap comments if you want to print the curr sub

	    #my $fmt = "%" . "$max.$max" . "s: %s (c: %s)\n";
	    #printf($fmt, $w2t[$line_ref->[1]], $line_ref->[0], $line_ref->[2]);

	    if ($line_ref->[0] =~ m/sub\s+/) #  == $wrap_sub)
	    {
		my $fmt = "\%$max.$max" . "s :%s (subname: %s) args:";
		printf($fmt,
		       $w2t[$line_ref->[1]],
		       $line_ref->[0],
		       $line_ref->[2]);
		foreach my $key (keys(%{$args{$line_ref->[2]}}))
		{
		    print "$key ";
		}
		print "\n";
# 		foreach my $key (keys(%args))
# 		{
# 		    print "subname:.$key.\n";
# 		    foreach my $sa (keys(%{$args{$key}}))
# 		    {
# 			print "$sa\n";
# 		    }
# 		}
	    }
	    else
	    {
		my $fmt = "%" . "$max.$max" . "s: %s\n";
		printf($fmt, $w2t[$line_ref->[1]], $line_ref->[0]);
	    }
	}
    }
    
    # Dump and exit.

    if ($_[1] == 1)
    {
	exit();
    }
    return $output;
}



sub compile_all
{
    my @tokens = tokenize($_[0]);

    my $output = compile_deft(\@tokens);

    my $shebang = gen_shebang();

    return "$shebang$output";
}


# replacment for the old CGI::escape
sub encode_string
{
    my $es = $_[0];
    # This was the working line:
    $es =~ s/(.)/sprintf("\\%3.3o",ord($1))/seg;

    # New experimental / ignoring regex:
    #$es =~ s/([^\/])/sprintf("\\%3.3o",ord($1))/seg;

    return $es;
}

# replacment for the old CGI::unescape which turned + into space.
sub decode_string
{
    my $ds = $_[0];
    $ds =~ s/\\(\d+)/sprintf("%c",oct($1))/seg;
    return $ds;
}

sub unescape
{
    $_[0] =~ s/([\"\'\`\/])(.*?)\1/$1.&decode_string($2).$1/ge;

    # second pass to get s///, etc.
    $_[0] =~ s/([\"\'\`\/])(.*?)\1/$1.&decode_string($2).$1/ge;
    return $_[0];
}



# If you don't instantiate the new query with "" as an argument,
# and the query is an <ISINDEX> query or if the query contains no
# ampersands, then you will always get a single parameter "keywords".
# Invoked from the command line, this seems to be $ARGV[0].
#
# However, if you instantiate with "" as an arg,
# then you get an empty set of vars instead of the CGI vars.

sub deft_cgi
{
    my $query = new CGI();
    my %ch = $query->Vars();
    $ch{qq} = $query;

#     my $filehandle = $query->upload('image_fn');
#     my $f_hr = $query->uploadInfo($filehandle);
    
#     print "Content-type: text/plain\n\n";
#     foreach my $key (keys(%{$f_hr}))
#     {
#  	print "$key:$f_hr->{$key}\n";
#     }

    # No external CGI vars are allowed to be internal vars.

    foreach my $key (keys(%ch))
    {
	if ($key =~ m/^\_/)
	{
	    # delete($ch{$key});
	}
    }

    my $have_keywords = 0;
    my $have_other = 0;
    foreach my $var (keys(%ch))
    {
	if ($var eq "keywords")
	{
	    $have_keywords = 1;
	}
	if ($var ne "keywords")
	{
	    $have_other = 1;
	}
    }
    
    # 2006-07-11 This extra column should be unnecessary. Much of the old
    # discussion of records with out any columns should be moot.


    # Make sure there is at least one column when we get ready to rewind.
    # See comments above unwind in st_lib.pl.
    # This has a couple of effects. 
    # First, it prevents the dreaded false record problem.
    # Second, it prevents users from using CGI to coopt _return.
    
    # $ch{'_return'} = 1;
    
    # This is see the comment at the top of this sub about the 'keywords' param.
    # Reverse the logic, and remove stuff we don't want in %ch instead
    # of copying to eenv.

    if ($have_keywords and ! $have_other)
    {
	delete($ch{keywords});
    }

    my %urh;
    my $run_once = 1;
    while(unwind(\%urh) || $run_once)
    {
	$run_once = 0;
	
	foreach my $var (keys(%ch))
	{
	    # $var must (should?) be interpolated in a string,
	    # but we can't remember why.
	    
	    set_eenv("$var", $ch{$var});
	}
	rewind(\%urh);
    }
}


# sub read_file
# {
#     my $file_name = $_[0];
#     my $date_flag = $_[1];
#     my @stat_array = stat($file_name);
#     if ($#stat_array < 7)
#       {
#         die "File $file_name not found\n";
#       }
#     my $temp;

#     # 2003-01-10 Tom:
#     # It is possible that someone will ask us to open a file with a leading space.
#     # That requires separate args for the < and for the file name. I did a test to confirm
#     # this solution. It also works for files with trailing space.
#     # 
#     # oldthink
#     # open(IN, "< $file_name");
#     # newthink:

#     open(IN, "<", "$file_name");

#     sysread(IN, $temp, $stat_array[7]);
#     close(IN);
#     if ($date_flag == 1)
#     {
# 	# Return a nice SQL compatible date.
# 	# stat: 9 mtime    last modify time in seconds since the epoch
# 	# We won't worry about timezones at this point.

# 	my @lt = localtime($stat_array[9]); 
# 	my $date = sprintf("%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d",
# 			1900+$lt[5],$lt[4]+1,$lt[3],$lt[2],$lt[1],$lt[0]);
# 	return ($temp,$date);
#     }
#     elsif ($date_flag == 2)
#     {
# 	# Return seconds since the epoch (so the returned date is easy to compare
# 	# to other dates).
# 	# stat: 9 mtime    last modify time in seconds since the epoch

# 	return ($temp,$stat_array[9]);
#     }
#     return $temp;
# }


# Need to track database handles, so we can open
# them once, instead of opening and closing them.

my %db_handles;

# Identical to get_db_handle in session_lib.pm.  New code assumes
# local .app_config, user has db, and there is no Deft system db.

# Transactions must be enabled for some of the code to work.
# Transactions are explicitly enabled by setting AutoCommit to zero.
# We always use a tcp connection, even to the localhost, so we always
# need the host name and port.

# MySQL ignores all the args except the connect string.  The MySQL
# connection failed unless the user and password were in the connect
# string. The Postgres driver conforms to the DBI documentation, and
# therefore requires the user and password arguments.

# Don't use SQL db logging here unless that logging doesn't call this
# to get its db handle.

sub deft_connect
{
    my $db_alias = $_[0]; # The name is an alias. See file .app_config
    if (! $db_alias)
    {
	my $str = sprintf("%s $0 session_lib.pm get_db_handle() must have an alias.", (caller(0))[3]);
	die "$str\n";
    }

    if (! exists($db_handles{$db_alias}))
    {
	my %cf = app_config($db_alias);
	
	my %vars;
	if (exists($cf{$db_alias}))
	{
	    ($vars{db_name},
	     $vars{dbms},
	     $vars{db_host},
	     $vars{db_port},
	     $vars{db_user},
	     $vars{db_password}) = split('\s+', $cf{$db_alias});
	    
	    $vars{alias} = $db_alias;

	    if (! $vars{db_name})
	    {
		die "Missing db info for alias:$db_alias from config:$cf{app_config}\n";
	    }
	}
	else
	{
	    die "No record for database $db_alias in $cf{app_config}.\n";
	}

	my $dbargs = {AutoCommit => 0, PrintError => 1};
	my $connect_string =
	    sprintf("dbi:%s:dbname=%s;host=%s;port=%s;user=%s;password=%s",
		    $vars{dbms},
		    $vars{db_name},
		    $vars{db_host},
		    $vars{db_port},
		    $vars{db_user},
		    $vars{db_password});

	$db_handles{$db_alias} =  DBI->connect($connect_string,
					       $vars{db_user},
					       $vars{db_password},
					       $dbargs);

	$connect_string =~ s/$vars{db_password}/*******/g;
	if ($DBI::err)
	{
	    my $str = sprintf("%s Couldn't connect to $vars{db_name}", (caller(0))[3]);
	    die "$str\n";
	}
    }
    return $db_handles{$db_alias};
    my $quiet_warnings = $DBI::err;
}

# This cleans all db handles, including the Deft (system) db handle
# which is hard coded as $db_handles{deft}

# sub clean_db_handles
# {
#     foreach my $dbh (values(%db_handles))
#     {
# 	$dbh->disconnect();
#     }
# }

sub check_and_traverse
{
    my $ac_file = $_[0];
    my $cf_hr = $_[1];
    my $cf_hide_hr = $_[2];
    my $ok_flag = 0;
    
    if (-e $ac_file)
    {
	my $all = read_file($ac_file); 
	# save visited file names for debugging.
	$cf_hr->{app_config} = "$ac_file";
	ac_core($all, $cf_hr, $cf_hide_hr);
	$ok_flag = 1;
    }

    my $xx = 0;
    while ($cf_hr->{redirect} && ($xx < 5))
    {
	my $all = read_file($cf_hr->{redirect});
	# save visited file names for debugging.
	$cf_hr->{app_config} .= ", $cf_hr->{redirect}";
	$cf_hr->{redirect} = "";
	ac_core($all, $cf_hr, $cf_hide_hr);
	$xx++;
    }
    return $ok_flag;
}

# Not exported.
sub ac_core
{
    my $all = $_[0];
    my $cf_ref = $_[1];
    my $cf_hide = $_[2];

    my %subs; #hash of things we are willing to substitute into config values.
    $subs{login} = login();
    
    # Break the file into lines. This means that a value cannot contain newlines.
    # If you need newlines, you'll need a more interesting parsing regex.

    my @lines;
    while($all =~ s/^(.*?)\n//)
    {
	my $line = $1;
	# Do not convert escaped octal sequences back to characters
	# until parsing is complete. Otherwise \075 "=" breaks the parser.
	
	$line =~ s/\#(.*)//g; 	# remove comments to end of line
	$line =~ s/\s*=\s*/=/g;	# remove whitespace around = 
	$line =~ s/\s+$//g;	# remove trailing whitespace
	$line =~ s/^\s+//g;	# remove leading whitespace
	
	# If there is anything left, push it.
	if ($line)
	{
	    push(@lines, $line);
	}
    }

    # The last line (or fragment), if there is one.
    if ($all)
    {
	$all =~ s/\#(.*)//g; 	# remove comments to end of line
	$all =~ s/\s*=\s*/=/g;	# remove whitespace around = 
	$all =~ s/\s+$//g;	# remove trailing whitespace
	$all =~ s/^\s+//g;	# remove leading whitespace
	
	push(@lines, $all);
    }

    foreach my $line (@lines)
    {
	# See Note 3 above.
	$line =~ s/(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)/exists($subs{$2})?$subs{$2}:$1/eg;

	$line =~ m/^((.*)=(.*))$/;
	my $name = $2;
	my $value = $3;

	$name =~ s/\\([0-9]{3})/chr(oct($1))/eg;
	$value =~ s/\\([0-9]{3})/chr(oct($1))/eg;
	$cf_ref->{$name} = $value;
    }
    
    if (exists($cf_ref->{hide}))
    {
	my @hide_list = split('\s+', $cf_ref->{hide});
	foreach my $hide (@hide_list)
	{
	    # Only overwrite if $cf_ref has a value!
	    if (exists($cf_ref->{$hide}))
	    {
		$cf_hide->{$hide} = $cf_ref->{$hide};
		delete($cf_ref->{$hide});
	    }
	}
    }

    # Hide needs a copy of the debug info too.
    # Hide does not need, nor does it get a copy of full_text (below).

    $cf_hide->{app_config} = $cf_ref->{app_config};



    # Each .app_config can supply a list of options to include in the
    # full_text field. This field's purpose is as record keeping only
    # (audit trail).  NOTE: This code must come after the hide values
    # have been deleted so that users cannot accidentally put hide
    # values into full_text output. Normal users might see full_text
    # so don't put anything private in there.

    if ($cf_ref->{full_text})
    {
	my @full_text_keys = split('\s+', $cf_ref->{full_text});
	my $tween = "";
	foreach my $key (@full_text_keys)
	{
	    $cf_ref->{full_text} .= "$tween$cf_ref->{$key}";
	    $tween = "\n";
	}
    }
}


# Note 3.
# After going through much testing for substituting variables into 
# template text for another application we created the following regex.
# The complicated looking regex with the eval flag will
# work for all variables that exist in the hash, understands beginning
# and end of lines, variables that contain numbers (and underscore),
# and it should be fast and efficient. It also supports better debugging and 
# than the alternatives (not shown here). The second regex handles octal
# character encoding, which is very handy in any template.

# app_config() takes an optional single arg. This clearly separates sensitive
# values from everything else. If someone doesn't ask for a particular hidden value,
# then no hidden values are returned.

# Environment variable APP_CONFIG overrides user .app_config
# Always read $path/.app_config if it exists.  Read .app_config in
# program directory and ./ but since ./ is read last, it's values
# will overwrite. If we have been redirected to another config
# file, read it (up to 5 redirects). Keep all the values from all
# the redirects. All kinds of things could go wrong with this
# (overwritten values, infinite loops, etc.).  Users should be
# careful with multiple config files. Local user .app_config will
# over write anything in the system .app_config. Note that the
# presence of an $ENV{APP_CONFIG} will prevent the user
# .app_config from being used.

# sub app_config
# {
#     my $single_return = $_[0];
#     my %cf;
#     my %cf_hide;
#     my $ok_flag = 0;

#     # This is not the same as the standard session_lib.pm. This is
#     # changed to use a "master" .app_config.  It only looks at the
#     # first .app_config found, although it follows redirections in any
#     # .app_config it finds (up to 5 redirects). My reasoning is that
#     # it is dangerous to look at all the available .app_config files
#     # due to overwrites. Instead we should look at the first
#     # .app_config and ignore the rest. If the user wants more than one
#     # file read, then the user needs to use explicit redirects.

    
#     if ($ENV{APP_CONFIG})
#     {
# 	$ok_flag = check_and_traverse($ENV{APP_CONFIG}, \%cf, \%cf_hide);
#     }
#     elsif (-e "./.app_config")
#     {
# 	$ok_flag = check_and_traverse("./.app_config", \%cf, \%cf_hide);
#     }
#     elsif ( -e "$FindBin::Bin/.app_config")
#     {
# 	$ok_flag = check_and_traverse("$FindBin::Bin/.app_config", \%cf, \%cf_hide);
#     }

#     if (! $ok_flag)
#     {
# 	print "Cannot find .app_config\n";
# 	write_log("$0 Error: Cannot find .app_config");
# 	exit(1);
#     }

#     # If we have a single_return, get it from the hide hash,
#     # clear out everything except the asked for field and "app_config"
#     # and return the hide hash instead of the usual %cf.

#     if ($single_return)
#     {
# 	if (! exists($cf_hide{$single_return}))
# 	{
# 	    my $output = "$0 app_config:\"$single_return\" not in \"hide\" for $cf_hide{app_config}\nkeys\n";
# 	    foreach my $key (keys(%cf_hide))
# 	    {
# 		$output .= "$key\n";
# 	    }
# 	    die "$output";
# 	}

# 	foreach my $key (keys(%cf_hide))
# 	{
# 	    if ($key ne $single_return &&
# 		$key ne "app_config")
# 	    {
# 		delete($cf_hide{$key});
# 	    }
# 	}

# 	return %cf_hide;
#     }
#     else
#     {
# 	return %cf;
#     }
# }


#
# select($config,$fields,$tables,$where);
# 
sub sql_select
{
    my $which_db = $_[0];
    my $fields_str = $_[1];
    my $tables_str = $_[2];
    my $where_str = $_[3];
    my $dbh = deft_connect($which_db);

    my @fields = split(',', $fields_str);

    my $question_marks;
    foreach my $item (@fields)
    {
	$item =~ s/\s*(\w*)\s*/$1/;
	$question_marks .= '?,';
    }
    chop($question_marks); # remove that trailing comma

    my $sql = "insert into $tables_str ($fields_str) values ($question_marks)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { write_log("Prepare fails on:$sql\n$DBI::errstr\n"); exit(1); }
    
    my %urh;
    while(unwind(\%urh))
    {
	# Love those list slices.
	# This needs work.

	$sth->execute(@{slice_eenv("\@fields")});
	if ($dbh->err()) { write_log("Execute fails on:$sql\n$DBI::errstr\n"); exit(1); }

	# Need to get the new primary key value here.

	$dbh->commit();
    }
    # Needs to be cached.
    #$dbh->disconnect();
}


sub sql_insert
{
    my $which_db = $_[0];
    my $table = $_[1];
    my $field_string = $_[2];
    my $dbh = deft_connect($which_db);

    my @fields = split(',', $field_string);

    my $question_marks;
    foreach my $item (@fields)
    {
	$item =~ s/\s*(\w*)\s*/$1/;
	$question_marks .= '?,';
    }
    chop($question_marks); # remove that trailing comma

    my $sql = "insert into $table ($field_string) values ($question_marks)";
    my $sth = $dbh->prepare($sql);
    if ($dbh->err()) { write_log("Prepare fails on:$sql\n$DBI::errstr\n"); exit(1); }
    
    my %urh;
    while(unwind(\%urh))
    {
	# Love those list slices.
	# This needs work

	$sth->execute(@{slice_eenv("\@fields")});
	if ($dbh->err()) { write_log("Execute fails on:$sql\n$DBI::errstr\n"); exit(1); }

	# Need to get the new primary key value here.

	$dbh->commit();
    }
    # Needs to be cached.
    #$dbh->disconnect();
}


# Note 3
# do_sql_simple() is supposed to do a join with the existing
# Deft stream. However, if you aren't supplying a query with at least one
# column from the stream, then the join is not well defined and you'll
# get a cartesian product of the two data sets (the rows of the 
# stream multiplied by the rows of the query).

# For the same reasons that SQL subqueries must have an alias,
# do_sql_simple will exit if asked to overwrite an existing column.
# You must use different column names (SQL "as") to avoid this issue.

# Note 4
# In the old days when we just warned
# we allowed overwriting of fields with undef values.
# We don't do that now. This was the extra clause in the
# if statement below:
# && defined(get_eenv($key)))

sub do_sql_simple
{
    my $which_db = $_[0];
    my $pkey_specifier = $_[1]; # field name comma sequence name
    my $sql_template = $_[2];

    my $dbh = deft_connect($which_db);

    # Change all ' to \' and we'll change them back later.
    $sql_template =~ s/\'/\&sq\;/sg; 

    # We might have zero records, so we have to
    # run at least once, even if unwind returns zero.

    my %urh;
    my $run_once = 1;
    my $ok = 1;
    while(unwind(\%urh) || $run_once)
    {
	my $eenv_ref = get_ref_eenv();

	$run_once = 0;

	# Interpolate first.
	# See the huge comment in runt.pl sub prep. (which may be badly out of date)

	# 2006-11-25 twl
	# Substitute place holders for quoted variables.
	# This should leave quoted literals unchanged.

	my $sql = $sql_template;
	my @value_list;
	my $output;
	while($sql =~ s/\&sq;\$(.*?)\&sq;/?/)
	{
	    if (exists_eenv($1))
	    {
		push(@value_list, get_eenv($1));
		$output .= get_eenv($1) . "\n";

	    }
	    else
	    {
		push(@value_list, $1);
		$output .= "$1\n";
	    }
	}

	# 2006-11-25 twl. Comment out two extra lines of code.
	# No longer necessary to have octal literals in SQL
	# No extra single quotes are in the SQL
	# $sql =~ s/\\([0-9]{3})/chr(oct($1))/eg;
	# $sql =~ s/\'/\\\'/sg; # quote all single quotes

	# Now that the SQL is clean, substitue $vars as appropriate.
	$sql =~ s/\&sq\;/\'/sg; # un-encode prior single quotes that were literals

	# aug 27 2008 Need to check for null values in the record. 
	# If null for a variable used in the SQL, then skip, and unwind again.
	# $sql =~ s/(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)/exists_eenv($2)?get_eenv($2):$1/eg;

	my $regex = '(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)';
	my $orig = $sql;
	while (($orig =~ m/(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)/g) && $ok)
	{
	    if (exists_eenv($2))
	    {
		if (get_eenv($2))
		{
		    my $subst = get_eenv($2);
		    $sql =~ s/(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)/$subst/;
		}
		else
		{
		    $ok = 0;
		    next;
		}
	    }
	}

	# Only run the SQL if we are ok after the var substitution.
	# We are doing a next from the middle of a long loop. This
	# could be structured better.

	if (! $ok )
	{
	    rewind(\%urh);
	    $ok = 1;
	    next;
	}

	my $sth = $dbh->prepare($sql);
	
	if ($dbh->err()) { write_log("Prepare fails on:$sql\n$DBI::errstr\n"); exit(1); }
	
	my $rows = $sth->execute(@value_list);
	if ($dbh->err()) { write_log("Execute fails on:$sql\n$DBI::errstr\n"); exit(1); }
	# Necessary for inserts when we want the primary key value after the insert?

	if ($pkey_specifier)
	{
	    (my $pk, my $seq) = split(',',$pkey_specifier);
	    if (! $pk || ! $seq)
	    {
		write_log("error: do_sql_simple, missing primary key arg: need sequence and target column. spec:$pkey_specifier");
		exit(1);
	    }
	    set_eenv($pk, sql_currval($dbh, $seq)); # see above
	}

	# If we have non-zero number of fields, and and we have non-zero rows
	# then we must have executed a select statement. Make new rows with the results.

	if ($sth->{NUM_OF_FIELDS} > 0 && $rows > 0)
	{
	    my $first_row_flag = 1;
	    while(my $hr = $sth->fetchrow_hashref())
	    {
		set_ref_eenv($eenv_ref);
		my $error_keys = "";
		foreach my $key (keys(%{$hr}))
		{
		    # See note 4 above.
		    if ($first_row_flag && exists_eenv($key) && get_eenv($key))
		    {
			# See note 3 above.
			$error_keys .= " $key";
		    }
		    set_eenv($key, $hr->{$key});
		}
		if ($first_row_flag && $error_keys)
		{
		    write_log("Error: do_sql_simple() overwrites col(s) $error_keys\n    $sql");
		    exit(1);
		}
		$first_row_flag = 0;
		rewind(\%urh);
	    }
	}
	else
	{
	    rewind(\%urh);
	    $dbh->commit();
	}
    }
    # $dbh is cached, so don't disconnect.
}


sub keep_core
{
    my @save_list = @{$_[0]};
    my $warn_flag = 0;
    my %new_data;

    # Used to throw out system vars we didn't know about.
    # That was very bad.

    die "keep_core needs a list of internal cols in the table\n";

    foreach my $var (@save_list)
    {
	if ($warn_flag && ! exists_eenv($var))
	{
	    write_log("Warning keep(): $var nonexistant in record");
	    $warn_flag = 0;
	}
	$new_data{$var} = get_eenv($var);
    }
    set_ref_eenv(\%new_data);
}

sub keep_clean
{
    die "common_lib.pl:keep_clean() deprecated\n";
}


# Keep only vars listed in arg zero.
# Strip all vars from the record.

sub keep
{
    my $save_str = $_[0];
    $save_str =~ s/\s+//g; # remove whitespace
    my @save_list = split(',', $save_str);

    my %urh;
    while(unwind(\%urh))
    {
	keep_core(\@save_list);
	rewind(\%urh);
    }
    return ;
}


sub dump_stream
{
    my $label = $_[0];
    my $d_cols = $_[1];
    my $max_width = 60;
    my $min_width = 15;
    my $quiet_warnings = $::in_stream;

    print "Content-type: text/html\n\n<html><body><pre>\n";
    print "Label:$label input stream:$::in_stream\n";

    # dump column list    
    my @dcl;
    if ($d_cols)
    {
	@dcl = sort(split(',', $d_cols));
    }
    else
    {
        # this is not quite right.
        @dcl = sort(user_keys_eenv());
    }

    my @recs;
    my %field_names;
    my $count = 0;
    set_view_list(@dcl);
    memoz();
    treset();
    while(unwind())
    {
	my @sys_cols;
	
	push(@recs, get_ref_eenv());

        foreach my $item (@dcl)
        {
            push(@sys_cols, $item);
        }

	foreach my $field (@sys_cols)
	{
	    my $field_val = get_eenv($field);
	    my $f_len = length($field_val);
	    if ($f_len > $max_width)
	    {
		$f_len = $max_width;
		$field_val = substr($field_val, 0, $max_width);
	    }

	    my $n_len = length($field);
	    my $w_len;
	    if ($f_len > $n_len)
	    {
		$w_len = $f_len;
	    }
	    else
	    {
		$w_len = $n_len;
	    }

	    if (!exists($field_names{$field}))
	    {
		$field_names{$field} = $f_len;
	    }
	    if (0)
	    {
		if (! $field)
		{
		    write_log("Warning: dump_stream field name is null.");
		}
		else
		{
		    # Checking a var against undef() or another ! defined
		    # var doesn't work. So, assign the val to a variable,
		    # and test the variable.

		    my $val = get_eenv($field);
		    if (! defined($val))
		    {
			write_log("Warning: dump_stream get_eenv() returns undef for field:$field");
		    }
		}
	    }
	    if ($w_len < $min_width)
	    {
		$w_len = $min_width;
	    }
	    if ($w_len > $field_names{$field})
	    {
		$field_names{$field} = $w_len + 2;
	    }
	}    
	$count++;
	rewind();
    }

    # Column headings

    if (0)
    {
	foreach my $field (sort(keys(%field_names)))
	{
	    my $fmt = " \%$field_names{$field}\.$field_names{$field}s ";
	    printf($fmt, $field); 
	}
	print "\n";
    }
    # record values

    my $xx = 1;
    foreach my $hr (@recs)
    {
	# print "eenv: $hr\n";
	foreach my $field (sort(keys(%field_names)))
	{
	    my $field_val = $hr->{$field};

	    $field_val =~ s/\0/\\0/sg; # quote all nulls. It is a CGI thing.
	    $field_val =~ s/[\000-\037]//sg;  # don't allow control chars in output;

	    # This is obscure and irritating.
	    # < needs to be quoted, but the raw text quoting
	    # fouls up the spacing. Might be easier to
	    # render this as text-plain.

	    $field_val =~ s/</x/g; 
	    $field_val =~ s/>/x/g;

	    my $fmt = " \%$field_names{$field}\.$field_names{$field}s ";
	    if (1)
	    {
		print "($xx) $field = $field_val\n";
	    }
	    else
	    {
		printf($fmt, $field_val); 
	    }
	}
	print "\n";
	$xx++;
    }

    print "Count:$count\neor\n";

    print "</pre></body></html>\n";
}



# This will now have identical args to crush_on

sub distinct_on
{
    my $op_code = $_[0];
    my $agg_str = $_[1];
    my $dis_str = $_[2];
    my @agg_vars;
    if ($agg_str ne '')
    {
	@agg_vars = split(',', $agg_str);
    }
    my @dis_vars = split(',', $dis_str);

    my %row_val;

    my %urh;
    treset();
    while(unwind(\%urh))
    {
	my $key;
	if (@agg_vars)
	{
	    if ($agg_vars[0] eq 'ALL') 
	    {
		$key = 'all rows being aggregated';
	    }
	    else
	    {
		$key = slice_key(\@agg_vars);
	    }
	}
	else # we will now aggregate on everything that isn't being crushed
	{
	    $key = join(', ', @{neg_slice_keys(\@dis_vars)});
	}
	push @{$row_val{$key}{row}}, get_ref_eenv();
	foreach my $dvar (@dis_vars)
	{
	    push @{$row_val{$key}{$dvar}}, get_eenv($dvar);
	}
    }
    foreach my $key (keys(%row_val))
    {
	my @rows = @{$row_val{$key}{row}};
	delete $row_val{$key}{row};
	foreach my $row (@rows)
	{
	    set_ref_eenv($row);	    
	    foreach my $col (keys(%{$row_val{$key}}))
	    {
		my $val = eval "$op_code(\@{\$row_val{\$key}{\$col}});";
		set_eenv($col, $val);
	    }
	    rewind(\%urh);
	}
    }
}

# list of columns right now, for use later to crush on.
sub clist
{

}


# Debugging use only (it prints).
# Count the rows. Probably not meaningful
# unless the count is based on distinct values 
# in a column set, that is: a relation.

sub rows
{
    my $xx = 0;
    my %urh;
    treset();
    while(unwind(\%urh))
    {
	$xx++;
	rewind(\%urh);
    }
    print "$_[0]:$xx\n";
}


sub delete
{
    my %urh;
    treset();
    while(unwind(\%urh))
    {
	# Nothing here.
	# No rewind either.
    }
}


# distinct that crushes rows
# This isn't broken.
# Noah wrote this, but he's blaming Tom.
# Rename this to "crushenstein" and create a simpler crush_on
# limited to... crushing rows.

sub crush_on
{
    my $op_code = $_[0]; # min, max? whatever (look it up).
    my $agg_str = $_[1]; # crush rows unique for this arg.
    my $dis_str = $_[2]; # crush rows on cols not named.

    my @agg_vars;
    if ($agg_str ne '')
    {
	@agg_vars = split(',', $agg_str);
    }
    my @dis_vars = split(',', $dis_str);

    my %row_val;

    my %urh;
    treset();
    while(unwind(\%urh))
    {
	my $key;
	if (@agg_vars)
	{
	    if ($agg_vars[0] eq 'ALL') 
	    {
		$key = 'all rows being aggregated';
	    }
	    else
	    {
		$key = slice_key(\@agg_vars);
	    }
	}
	else 
	{
	    # we will now aggregate on everything that isn't being crushed
	    $key = join(', ', @{neg_slice_eenv(\@dis_vars)});
	}

	$row_val{$key}{row} = get_ref_eenv();

	foreach my $dvar (@dis_vars)
	{
	    push @{$row_val{$key}{$dvar}}, get_eenv($dvar);
	    my $val = get_eenv($dvar);
	}
	go_unwind();
    }

    foreach my $key (keys(%row_val))
    {
	set_ref_eenv($row_val{$key}{row});
	delete($row_val{$key}{row});
	foreach my $col (keys(%{$row_val{$key}}))
	{
	    my $val = eval "$op_code(\@{\$row_val{\$key}{\$col}});";
	    set_eenv($col, $val);
	}
	rewind(\%urh);
    }
}

sub sum
{
    my $out;
    foreach my $item (@_)
    {
	$out += $item;
    }
    return $out;
}

sub count
{
}

sub min
{
    my @out = sort {$a <=> $b} @_;
    return shift @out;
}

sub max
{
}


sub logdir
{
    foreach my $dir (@{$_[0]})
    {
	if (-d "$dir")
	{
	    return $dir;
	}
    }
    # Otherwise what? One of those directories had better exist.
}

sub mean
{
    my $source = $_[0];
    my $destination = $_[1];

    my @rows;
    my $sum = 0;
    my $count = 0;
    my %urh;
    treset();
    while(unwind(\%urh))
    {
	push(@rows, get_ref_eenv());
	$sum += get_eenv($source);
	$count++;
    }
    my $ave; 
    if ($count > 0)
    {
	$ave = $sum/$count;
    }
    else
    {
	$ave = 0;
    }
    foreach my $hash (@rows)
    {
	set_ref_eenv($hash);
	set_eenv($destination, $ave);
	rewind(\%urh);
    }
}


# $eval_col = " \'find $dir -name \"$proto*.jpg\"\' ";
# naive_make_row("eval_col", "new_col");

sub naive_make_row
{
    my $eval_col = $_[0];
    my $new_col = $_[1];

    # $dir = get_eenv($dir); # it's a col name
    # print "d:$dir /usr/bin/find $dir -name=\"$proto\"\n";
    # my @files = `/usr/bin/find $dir -name \"$proto\"`;

    my %urh;
    treset();
    while(unwind(\%urh))
    {
	my $eval_str = get_eenv($eval_col);
	my @elist = eval( $eval_str );
	chomp(@elist);

	foreach my $item (@elist)
	{
	        # Might be a good idea to see if $new_col exists,
	        # but we can do that later.
	    set_eenv($new_col, $item);
	    rewind(\%urh);
	}
    }
}

# scalar login.
# sub login
# {
#     # Someday the login could be more complex,
#     # i.e. we start using a real session.

#     my $login = "";

#     if (exists($ENV{REMOTE_USER}))
#     {
#         $login = $ENV{REMOTE_USER};
#     }
#     else
#     {
# 	$login = `/usr/bin/id -un`;
# 	chomp($login);
#     }
#     return $login;
# }


sub initdeft
{
    $deft_func{dispatch} = \&dispatch;
    $deft_func{delete} = \&delete;
    $deft_func{read_ws_data} = \&read_ws_data;
    $deft_func{clist} = \&clist;
    $deft_func{rows} = \&rows;
    $deft_func{deft_cgi} = \&deft_cgi;
    $deft_func{naive_make_row} = \&naive_make_row;
    $deft_func{duc} = \&duc;
    $deft_func{rerel} = \&rerel;
    $deft_func{self_select} = \&self_select;
    $deft_func{desc} = \&desc;
    # $deft_func{crush} = \&crush;
    $deft_func{mean} = \&mean;
    # $deft_func{agg_simple} = \&agg_simple; # see st_lib.pl
    $deft_func{if_simple} = \&if_simple;
    $deft_func{if_col} = \&if_col;
    $deft_func{cgi_make_row} = \&cgi_make_row;
    $deft_func{naive_make_col} = \&naive_make_col;
    $deft_func{sql_insert} = \&sql_insert;
    $deft_func{do_sql_simple} = \&do_sql_simple;
    $deft_func{keep} = \&keep;
    # $deft_func{keep_row} = \&keep_row;
    $deft_func{keep_clean} = \&keep_clean;
    $deft_func{crush_on} = \&crush_on;
    $deft_func{dcc} = \&dcc;
    $deft_func{distinct_on} = \&distinct_on;
    $deft_func{do_search} = \&do_search;
    $deft_func{dump_stream} = \&dump_stream;
    $deft_func{read_tab_data} = \&read_tab_data;
    $deft_func{render} = \&render;
    $deft_func{return_col} = \&return_col;
    $deft_func{return_true} = \&return_true;
    $deft_func{return_false} = \&return_false;
    $deft_func{run_core} = \&run_core;

    # @logdirs may be a site config value. Check/edit as necessary for your site.
    # Only one log dir is chosen, and they are checked in the order they appear here.
    # No trailing /

    my @logdirs;
    if (exists($ENV{USER}))
    {
	my $userid = $ENV{USER};
	@logdirs = (".",
		    "/home/$userid/public_html/deft",
		    "/home/$userid/deft",
		    "/home/$userid/public_html",
		    "/home/$userid");
    }
    elsif (exists($ENV{SCRIPT_FILENAME}))
    {
	my $script_path = $ENV{SCRIPT_FILENAME};
	$script_path =~ s/(.*)\/.*/$1/;
	@logdirs = ("$script_path");
    }

    $::logdir = logdir(\@logdirs);
}


# Assume that all hosts have the same availability from each other
# e.g. that no hosts are excluding connections to any other hosts.
#
# -w 1 time out after one second
# -z just check, don't connect
# -v print a message to stderr
# 2>&1 to redirect stderr to stdout so we can capture it.

sub check_hosts
{
    my @hosts = @{$_[0]};
    my $port = $_[1];
    my @active_hosts;
   
    foreach my $host (@hosts)
    {
	print "checking $host\n";
	my $temp = `/usr/bin/nc -w 1 -zv $host $port 2>&1`;
	if ($temp =~ m/open/)
	{
	    push (@active_hosts, $host);
	}
    }
    return @active_hosts;
}


sub open_peer
{
    my $host = $_[0];
    my $port = $_[1];
    my $kidpid;
    my $handle; 
    my $line;
    my $iaddr;
    my $paddr;
    my $peer_handle;

    if ($port =~ /\D/)
    {
	$port = getservbyname($port, 'tcp');
    }
    if (! $port)
    {
	write_log("No port in open_peer\n");
	exit();
    }
    
    $iaddr = inet_aton($host);
    if ( ! $iaddr)
    {
	write_log("no host: $host");
	exit();
    }
    $paddr   = sockaddr_in($port, $iaddr);
    
    my $proto   = getprotobyname('tcp');
    my $max_fc = 2;
    my $fail_count = 0;
    my $c_flag = 0;
    while ($c_flag == 0 && $fail_count < $max_fc)
    {
	if (! socket($peer_handle, PF_INET, SOCK_STREAM, $proto))
	{
	    write_log("socket fails: $!");
	    exit();
	}
	if (! connect($peer_handle, $paddr))
	{
	    my $error_message = $!;
	    {
		write_log("open_peer connect to ph:$peer_handle pa:$paddr failed: $error_message");
		exit();
	    }
	}
	else
	{
	    $c_flag = 1;
	}
    }
    if ($fail_count >= $max_fc)
    {
	write_log("Couldn't launch daemon. Exiting.");
	exit(1);
    }
    my $oldfh = select($peer_handle);
    $| = 1;
    select($oldfh);
    return $peer_handle;
}


sub close_peer
{
    # It may not do much, but at least it makes Perl stop warning about
    # the global being used only once in deftd.pl

    close($_[0]);
}


# Turn everything in eenv into a scalar in our name space.

sub restorevars
{
    my $have_data;
    $have_data = 0;
    foreach my $var (user_keys_eenv())
    {
	no strict;
	#
	# Don't try to restore $1, $2, etc.
	# Shouldn't restore any of Perl's built in variables.
	# 
	if ($var !~ m/^\d+$/)
	{
	    $have_data = 1;
	    $$var = get_eenv($var);
	}
    }
    return $have_data;
}


# sub write_log
# {
#     my $var;
#     $var = $$; # process id

#     # 2006-07-01 Fix the log path to always be the same
#     # directory. Period. Don't try to do something smart.

#     #$::logdir = "/tmp";

#     # Might be able to use FindBin for the log path.
#     # $::_d_path is set at the beginning of all compiled .pl

#     $::logdir = $::_d_path; 

#     my $id = `/usr/bin/id`;
#     chomp($id);
#     my $fname = "$::logdir/err_$var" . ".out";
#     if (! open(ERR, ">> $fname"))
#     {
# 	my $cwd = `/bin/pwd`;
# 	die "error:$!\non:$fname\ncwd:$cwd";
#     }
#     print ERR "$_[0]\n";
#     close(ERR);
# }


1;
