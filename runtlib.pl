#!/opt/local/bin/perl

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
use Storable qw(freeze thaw);
my $distinct;
my @sort;
my %sort_vals;
my %sort_ties;
my $newvar;
my $where_eval;

my %once;

my $first_flag = 1;
sub keycmp
{
    my $key_a = $_[0]; # $sortvals($bpath}

    my $return_val = 0;
    my $sort_type;
    for(my $sv_counter = 0; ($sv_counter <= $#sort) && (! $return_val); $sv_counter++)
    {
	my ($s_order,$s_type) = split('',$sort[$sv_counter][1]);
	if ($s_order && $s_type)
	{
	    #write_log("so:$s_order st:$s_type");
	    if ($s_type eq 'n')
	    {
		if ($s_order eq 'a')
		{
		    $return_val = (get_eenv_handle($sort[$sv_counter][0], $key_a) <=> 
				   get_eenv($sort[$sv_counter][0]));
		}
		else
		{
		    $return_val = (get_eenv($sort[$sv_counter][0]) <=> 
				   get_eenv_handle($sort[$sv_counter][0], $key_a));
		}
	    }
	    else
	    {
		if ($s_order eq 'a')
		{
		    $return_val = (lc(get_eenv_handle($sort[$sv_counter][0], $key_a)) cmp 
				   lc(get_eenv($sort[$sv_counter][0])));
		}
		else
		{
		    $return_val = (lc(get_eenv($sort[$sv_counter][0])) cmp 
				   lc(get_eenv_handle($sort[$sv_counter][0], $key_a)));
		}
	    }
	}
	else
	{

	    #
	    # WriteError("st:.$sort_type.");
	    # return zero because with no sort_type, all are equal?
	    #
	    $return_val = 0;
	}
# 	if ($sort[$sv_counter][0] eq "page_break")
# 	{
# 	    my $key_b = get_eenv($sort[$sv_counter][0]);
# 	    my $ka_ref = $key_a;
# 	    my $kb_ref = get_ref_eenv();
# 	    write_log("nv:$newvar ka:$ka_ref kb:$kb_ref svc:$sv_counter sort:$sort[$sv_counter][0] a:$key_a->{$sort[$sv_counter][0]} b:$key_b r:$return_val");
# 	}
    }
    return $return_val;
}



# We want a list slice 1,2,3 of eenv
# Believe it or not, an array is a legitimate arg for a hash slice.
# Change join's first arg from " ," to ", " assuming Noah made a typo.
#
# It is possible that this will be called with values that do not result 
# in a non-null list slice. Use a regex so we don't return
# ", " since there are things calling keystr() that rely on non-matching 
# list slice to return an empty string.

sub keystr
{
    my @temp = split(',', $_[0]);
    my $slice_ref = slice_eenv(\@temp);

    # This if statement is only here to handle null records,
    # instead of the regex we used to use.
    # When we can handle null records, keystr() will never 
    # be called on a null record because null records won't rewind.
    # Without some kind of null record (or null keystr()) test, records
    # without any of the aggregated columns will dcc() as true and will emit.

    if ($#{$slice_ref} == -1)
    {
	return undef;
    }
    my $eval_this = join(', ', @{$slice_ref});
    return $eval_this;
}

# sub update_sort_vals
# {
#     my $exists_value = $::exists{keystr($distinct)};
#     if ($sort[2])
#     {
# 	# eval aggregator
#     }
# }


# Build the key for the current record. This is 
# essentially a binary tree branching path with 'a' and 'g'
# the two directions at each node. We use the character 'c' to
# denote a tie in the tree. Stablility is meaningless in Deft
# since we don't care about row order. This sort (get_bpath) is not
# stable on row order for tied rows.

# Note 1
# Global %sort_ties keeps a running list of ties.
# This code extents the use of 'c'. The new, additional use is 
# to indicate a tie in an 'ag' string. The only previous use was
# as the join character of t strings.
# You may recollect that 't' string that contain doc structure 
# (e.g. portions of the template controlled by the control spec).
# 'ag' strings contain row ordering.

sub get_bpath
{
    my $keystr = $_[0];

    my $bpath = 'g';
    my $cmp_val = 1;
    while (exists($sort_vals{$bpath}))
    {
	$cmp_val = keycmp($sort_vals{$bpath});
	if ($cmp_val > 0)
	{
	    $bpath .= 'a';
	}
	elsif ($cmp_val < 0)
	{
	    $bpath .= 'g';
	}
	else
	{
	    # Tie detected. See Note 1 above.
	    
	    $sort_ties{$bpath}++;
	    $bpath .= 'c' x $sort_ties{$bpath};
	}
    }
    # Save two assignments and memory for the get_ref_eenv() 
    # when there is a tie.
    # Get Noah to explain this in more detail. the following
    # if only hits where there is *not* a tie, and not visa-versa.

    if ($cmp_val)
    {
	$sort_vals{$bpath} = get_ref_eenv();
    }
    $::exists{$keystr} = $bpath;
    return ($bpath);
}


# Aggregation and where are evaluated separately.
# Records which fail the where eval are not processed further,
# however, they still need a valid value for $newvar, and that value is zero.
# Zero will prevent them from emitting in the render phase.
# Note: any where test of the parent must be applied to children.

# Existing values have the same $newvar as the value had when we first found it.
# E.g. all duplicates have same newvar.

# Check defined($ks_val) instead of just $ks_val since keystr() might return
# a value of zero or simply a null string. If there are none of the aggregated
# columns in the current record, keystr() will return undef.

sub emit
{
    my %urh;
    while(unwind(\%urh))
    {
	my $bpath = 0; # Records which fail the where, don't emit.

	if (eval($where_eval))
	{
	    my $ks_val = keystr($distinct);
	    if (defined($ks_val) && exists($::exists{$ks_val}))
	    {
		$bpath = $::exists{$ks_val};
		#print "exists:$newvar gets:$hash{$newvar}\n";
	    }
	    else
	    {
		$bpath = &get_bpath($ks_val);
		#print "new:$newvar gets:$hash{$newvar}\n";
	    }
	}
	set_eenv($newvar, $bpath);
	rewind(\%urh);
    }
}


# Declare Control Column
# All the action starts and ends here.
# Repeating template
#
# dcc("distinct_t",             # name of new column aka newvar
#     "title",                  # dictinct on this column aka agg_spec
#     [""],                     # where 
#     ["rank,dn", "title,at"]); # sort
#
# dcc("distinct_dt",
#     "description,title",
#     [""],
#     [","]);

sub dcc
{
    $newvar = $_[0];
    $distinct = $_[1];
    my @where_arg = @{$_[2]};
    my @sort_arg = @{$_[3]};
    undef(%::exists);
    undef(@sort);
    undef(%sort_vals);
    undef(%sort_ties);
    $where_eval = "1";

    if ($distinct =~ m/\s+/)
    {
	write_log("arg 1 to dcc() aggregate $distinct must not contain whitespace");
	die "arg 1 to dcc() aggregate $distinct must not contain whitespace\n";
    }

    # The aggregator must not include records for which the
    # the keystr() is empty for $distinct. Remember that $distinct can 
    # be something like "$title,$description" and $distinct is used
    # as an array slice. 

    my $where_tween = "&&";
    foreach my $wc (@where_arg)
    {
	if ($wc =~ m/(.*?)\s+(.*)/)
	{
	    # This will be eval'd in emit(); It must be sypatico with the runtime
	    # environment of emit().
	    $where_eval .= " $where_tween (get_eenv('$1') $2)";
	}
    }
    my $xx = 0;
    foreach my $sa (@sort_arg)
    {
	my @temp = split(',',$sa);
	$sort[$xx][0] = $temp[0];
	$sort[$xx][1] = $temp[1];
	$xx++;
    }
    emit();
}



# Very similar to emit() but not a pass thru aggregation
# like emit. See notes with emit.
# Save structure data in %table. A couple of loops
# at the end handle the aggregation and rewinding.
# Currently only supports ordinal numbering. Tie values
# get the same ordninal number.

sub emit_desc
{
    my $base_val = $_[0];
    my $function = $_[1];
    my %table; # hash of lists?
    my %urh;
    while(unwind(\%urh))
    {
	# printf("we:$where_eval mr:%s\n", get_eenv('main_rank'));
	if (eval($where_eval))
	{
	    # print "di:$distinct\n";
	    my $ks_val = keystr($distinct);
	    if ($ks_val && exists($::exists{$ks_val}))
	    {
		# Yes, the table must contain a real copy of eenv.
		push(@{$table{$::exists{$ks_val}}}, get_ref_eenv());
		#print "exists:$newvar gets:$hash{$newvar}\n";
	    }
	    else
	    {
		my $bpath = &get_bpath($ks_val);
		push(@{$table{$bpath}}, get_ref_eenv());
		#print "new:$newvar gets:$ee_ref->{$newvar}\n";
	    }
	}
	else
	{
	    # An old bug here this caused keys like ttc0ctttcagacttt
	    # Zero in a final key is bad.
	    push(@{$table{0}}, get_ref_eenv());
	}
    }

    # undef newvar for rows that don't get ordinal values.

    foreach my $hr (@{$table{0}})
    {
	set_ref_eenv($hr);
	set_eenv($newvar, undef);
	rewind(\%urh);
    }
    
    # The ordinal base value.

    my $xx;
    if (ref($base_val) eq 'CODE')
    {
	$xx = &$base_val;
    }
    else
    {
	$xx = $base_val;
    }

    # Get rid of null keys in %table so any keys still in %table
    # are keys we care about. Saves if's below.

    delete($table{0});

    # Add post "c" so that keys will alphabetically sort properly.
    # Then delete the old keys.

    foreach my $key (keys(%table))
    {
	my $newkey = "c" . $key . "c"; # shortcut for what runt does with keys
	$table{$newkey} = $table{$key};
	delete($table{$key});
    }

    # The loop above could be merged into the sort below.
    # Run through unique keys. 
    # Set our eenv to an eenv previously copied that is a row
    # to which we'll be assigning an ordinal. Assign the ordinal.

    my @order = sort(keys(%table));
    my $key = shift @order;
    $xx = desc_rewind(\%urh, \%table, $key, $base_val);
    while ($key = shift @order)
    {
	$xx = desc_rewind(\%urh, \%table, $key, $function, $xx);
    }
}

# Put $urh at position zero since desc_rewind is called with var args.

sub desc_rewind
{
    my $urh = $_[0];
    my $table = $_[1];
    my $key = $_[2];
    my $function = $_[3];
    my $xx = $_[4];

    my $hr = shift @{$table->{$key}};
    set_ref_eenv($hr);
    if (ref($function) eq 'CODE')
    {
	restorevars(); # Huh? Was restore_vars
	$xx = &{$function}($xx);
    }
    else
    {
	$xx = $function;
    }
    set_eenv($newvar, $xx);
    rewind($urh);
    foreach my $hr (@{$table->{$key}})
    {
	set_ref_eenv($hr);
	set_eenv($newvar, $xx);
	
	# debug
	#my $nv = get_eenv($newvar);
	#my $po = get_eenv("page_order");
	#write_log("nv:$nv po:$po k:$key");
	
	rewind($urh);
    }
    return $xx;
}

# declare explicit structure column
# Aggregating version of dcc.
# Useful for creating ordinal (line number) columns
#
# desc("distinct_t",            # name of new column aka newvar
#     "title",                  # dictinct on this column aka agg_spec
#     [""],                     # where 
#     ["rank,dn", "title,at"]); # sort
# desc("distinct_t",            # name of new column aka newvar
#     "title",                  # dictinct on this column aka agg_spec
#     [""],                     # where 
#     ["rank,dn", "title,at"],  # sort
#     sub {$title},             # base value
#     sub {$_[0] . ", $title"}  # accumulative function
# desc("distinct_dt",
#     "description,title",
#     [""],
#     [","]);

sub desc
{
    $newvar = $_[0];
    $distinct = $_[1];
    my @where_arg = @{$_[2]};
    my @sort_arg = @{$_[3]};
    my $base_val = $_[4] || 1;
    my $function = $_[5] || sub {return ++$_[0]}; # must pre-increment. post-increment fails w/return.

    undef(%::exists);
    undef(@sort);
    
    $where_eval = "1";

    if ($distinct =~ m/\s+/)
    {
	$distinct =~ s/\s+//g;
	write_log("arg 1 to dcc() whitespace removed from aggregate $distinct");
	# die "arg 1 to dcc() aggregate $distinct must not contain whitespace\n";
    }

    # The aggregator must not include records for which the
    # the keystr() is empty for $distinct, becuase the return value of keystr()
    # a hash key. Empty hash keys are bad. Noah says we have a join string
    # therefore the empty key issue only applies to a single column. Multiple
    # null columns will yield a non-null string. Check this.
    # Remember that $distinct can be something like "$title,$description"
    # and $distinct is used as a hash slice, which is why $distinct can't
    # contain whitespace.

    my $where_tween = "&&";
    foreach my $wc (@where_arg)
    {
	if ($wc =~ m/(.*?)\s+(.*)/)
	{
	    # eval'd in emit_desc();
	    $where_eval .= " $where_tween (get_eenv('$1') $2)";
	}
    }
    my $xx = 0;
    foreach my $sa (@sort_arg)
    {
	my @temp = split(',',$sa);
	$sort[$xx][0] = $temp[0];
	$sort[$xx][1] = $temp[1];
	$xx++;
    }
    emit_desc($base_val,$function);
}


1;
