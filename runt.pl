#!/opt/local/bin/perl

# This software library is a portion of the Deft programming language
# and the DeFindIt Classic Search Engine.

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
use Cwd qw(abs_path getcwd);

# my @order;

my $root_key = 't';

# Get Noah to explain this. Later.
# Turn outhash keys into nesthash keys.
# ttcgct becomes tt|t

sub r_sort_spew
{
    # $_[0] is %thingy{key}
    #my %outhash = %{$_[0]{outhash}};
    #my %nest = %{$_[0]{nest}};

    my $nest_ref = $_[0];
    my $oh_ref = $_[1];

    my $final_output;
    my @sorted_outkeys = sort (keys(%{$oh_ref}));
    my $previous_okey;
    my $prev_stem = "";
    foreach my $okey (@sorted_outkeys)
    {
	# printf("okey:$okey oh:$oh_ref->{$okey}\n");
	my $okey_stem;
	if ($okey =~ m/(.*)c[ag]+ct/)
	{
	    $okey_stem = $1;
	}
	else
	{
	    $okey_stem = '';
	}
	if ($okey_stem && ($okey_stem eq $prev_stem))
	{
	    my $hashkey = $okey_stem;
	    $hashkey =~ s/(t+)[^t]/$1\|/g; # convert odd elements into |
	    $hashkey = "t|$hashkey";
	    if (exists($nest_ref->{$hashkey}{_tweens}))
	    {
		$final_output .= "$nest_ref->{$hashkey}{_tweens}";
	    }
	}
	$final_output .= "$oh_ref->{$okey}";
	$previous_okey = $okey;
	$prev_stem = $okey_stem;
    }
    return $final_output;
}

# 
# called from spew()
# Note 3.
#
# These previous regexs were all wrong in one way or another.
# Noah and I came up with two solutions. He kind of prefered
# to sort the hash keys by length in descending order
# and substitute based on that. My objection is that when 
# there is an error, the code can't necessarily tell what
# went wrong and therefore can't always make a useful
# error message. For the same reason, sanity checking is tricky.
# It also requires sorting the keys. Noah argued that the sorting method
# would allow us to support $vartext where text is not part of a variable
# name. My objection to that is that concatenating vars and text is
# a separate problem best solved by using octal character specs.
# The complicated looking regex below with the eval flag will 
# work for all variables that exist in the hash, understands beginning
# and end of lines, variables that contain numbers (and underscore),
# and it should be fast and efficient. The second regex handles the octal
# character encoding, which we needed regardless.

sub prep
 {
    my $tsub = $_[0];

    if (! scalar_eenv())
    {
	return $tsub; # incase we have an empty record set.
    }

    # See Note 3 above.

    $tsub =~ s/(?<!\\)(\$([\w\d]+))(?!=\w)(?!=\d)(?!=\z)/exists_eenv($2)?get_eenv($2):$1/eg;
    $tsub =~ s/\\([0-9]{3})/chr(oct($1))/eg;
    return $tsub;
}


#
# We want a list slice 1,2,3 of eenv
# Believe it or not, an array is a legitimate arg for a hash slice.
# Change join's first arg from " ," to ", " assuming Noah made a typo.
#
# It is possible that this will be called with values that do not result 
# in a non-null list slice. Use a regex so we don't return
# ", " since there are things calling r_keystr() that rely on non-matching 
# list slice to return an empty string.
#
sub r_keystr
{
    my @temp = split(',', $_[0]);
    my $eval_this = join(', ', @{slice_eenv(\@temp)});
    if ($eval_this =~ m/^(, )+$/)
    {
	$eval_this = "";
    }
    return $eval_this;
}


#
# In the loop:
#     for (my $xx = 1; $xx <= $#klist-1; $xx++)
# Skip root as usual.
# Don't do last element since leaf nodes always create output.
# Even values are the aggregating values of parents (aka how parents will sort).
# I would have thought that odd values were the parent of the even value's node,
# but Noah seems to have said that even value are always the parent index of 
# the current node.
#
# Tom 2003-07-01
# Using $klist[$#klist] works since the last element is always our parent's index.
# Noah says that $#klist is best because we want our parent's index every time,
# and not the parent index for which ever $xx we are on.
#
sub r_spew
{
    my $nest_key = $_[0];
    my $nest_ref = $_[1];
    my $oh_ref = $_[2];

    my @klist = split('\|',$nest_key);
    my $new_ohk;
    my $ohk_prefix = $klist[1]; # skip root, use first value
    my $cumulative_nk = $klist[0];

    $new_ohk = get_eenv($nest_ref->{$nest_key}{_agg_spec});

    # See the long comment above.

    for (my $xx = 1; $xx <= $#klist-1; $xx++)
    {
	# Some ancestor's nest_key.
	$cumulative_nk .= "|$klist[$xx]";
	my $vh_value = get_eenv($nest_ref->{$cumulative_nk}{_agg_spec});
	$ohk_prefix .= "c$vh_value" . "c" . $klist[$xx+1];
    }    

    if ($ohk_prefix =~ m/c0c/)
    {
	return;
    }

    # Even elements are $xx (what about the zeroth?)
    # Ask Noah:
    # Odd elements used to be $exists_counter values. What are they now?
    # Odd have the sort values i.e. keys from dcc(). Look at _chunk.

    foreach my $xx (0..$#{$nest_ref->{$nest_key}{_chunk}})
    {
	if (($xx % 2) == 0) # even 
	{
	    my @narr = @{$nest_ref->{"$nest_key"}{_chunk}};
	    my $tmp = "$ohk_prefix" . "c$new_ohk" . 'c' . ('t' x ($xx + 1));
	    $oh_ref->{"$tmp"} = prep($narr[$xx]);
	}
    }
}

sub r_spew_root
{
    my $nest_ref = $_[0];
    my $oh_ref = $_[1];

    my $xx;
    foreach $xx (0..$#{$nest_ref->{"$root_key"}{_chunk}})
    {
	if (($xx % 2) == 0)
	{
	    my @narr = @{$nest_ref->{"$root_key"}{_chunk}};
	    my $ohk = 't' x ($xx+1);
	    $oh_ref->{$ohk} = prep($narr[$xx]);
	}
    }
}



# It would be nice to sanity check here to see if children
# are emitting records that the parent didn't emit. This would be
# due to a failure on the part of the programmer who should have applied
# the children's "where" test to the parents.

# Note 1
# $order global. See render() below.
# Don't run element zero, which is the root key,
# and which is run above by r_spew_root().
# Need a comment for the following loop.

# Note 2
# 2004-11-25 Remove code that called r_spew_root() at least
# once even if there wasn't a record unwound. We assume
# there is at least one record. Sanity checking is the
# responsibility of other code.

sub r_emit
{
    my $first_flag = $_[0];
    my $nest_ref = $_[1];
    my $or_ref = $_[2];
    my $oh_ref = $_[3];
    
    my $key;
    if ($first_flag)
    {
	r_spew_root($nest_ref, $oh_ref);
    }

    # See Note 1 above.

    for(my $o_index=1; $o_index <= $#{$or_ref}; $o_index++)
    {
	$key = $or_ref->[$o_index];
	
	#my $temp = get_eenv($nest_ref->{$key}{_agg_spec});
	#printf("k:$key n:$nest_ref->{$key}{_agg_spec} t:$temp\n");

	if (get_eenv($nest_ref->{$key}{_agg_spec}))
	{
	    # Fix spew to do tweens?
	    r_spew($key, $nest_ref, $oh_ref);
	}
    }
    # See Note 2 above
}


# Make sure the files exist before stat'ing them.
# [9] is last mod date in seconds since the epoch.
# Don't bother thinking about re-compiling if the original file
# doesn't exist.

sub init_template
{
    my $template_name = $_[0];

    ($template_name, my $rnt_name) = munge_fn($template_name);

    if (! -f "$template_name")
    {
	write_log("Template doesn't exist or isn't a file:$template_name\n");
	clean_db_handles();
	exit(1);
    }
    
    my $tem_ts = (stat($template_name))[9];
    my $rnt_ts = (stat($rnt_name))[9];

    my $nest_ref;
    if ($tem_ts > $rnt_ts)
    {
 	$nest_ref = compile_rnt(in_file => $template_name,
				out_file => $rnt_name);
    }
    else
    {
 	$nest_ref = thaw(read_file($rnt_name));
    }
    return $nest_ref;
}


# Note 5
# We have to unwind to get the template name.
# We have to init the template before we can emit.
# We must init @order before emitting.

# r_emit() has a special case for first iteration,
# so pass in a first iteration flag.

# template_name to is fixed to have a full, absolute path
# th is Template Hash.
# %th is so simple there's no point in writing a comment.

sub render
{
    my $fn_var = $_[0];        # name of the variable that has the output file name.
    my $tn_var = $_[1];        # variable with template file name
    my $prefix = $_[2];        # header to send to output (i.e. http header)

    my $file_name;
    my $template_name;

    my %th; 
    my $first_flag;

    my %urh;
    while(unwind(\%urh))
    {
	$file_name = get_eenv($fn_var); 
	$template_name = get_eenv($tn_var);
	$template_name = abs_path($template_name);

	my $t_key = "$file_name\n$template_name";
	if (!exists($th{$t_key}))
	{
	    my %outhash;
	    $th{$t_key}{outhash} = \%outhash;
	    $th{$t_key}{file_name} = $file_name;
	    $th{$t_key}{nest} = init_template($template_name, 1);
	    @{$th{$t_key}{order}} = sort(keys(%{$th{$t_key}{nest}}));
	    $first_flag = 1;
	}
	else
	{
	    $first_flag = 0;
	}
	r_emit($first_flag,
	       $th{$t_key}{nest},
	       $th{$t_key}{order},
	       $th{$t_key}{outhash});

	rewind(\%urh);
    }

    # After going through the whole stream, and calling r_emit(),
    # outhash has all the output. Now it just needs final ordering
    # and gets contatenated into final_output.

    foreach my $key (keys(%th))
    {
	my $final_output = r_sort_spew($th{$key}{nest}, $th{$key}{outhash});
	my $file_name = $th{$key}{file_name};

	# If column $fn_var is empty or contains "-", render to stdout.
	# Else render to the file named in $fn_var.
	
	if (! $file_name || $file_name eq '-')
	{
	    print "$prefix$final_output\n";
	}
	else
	{
	    if (open(RENDER_OUT, ">", "$file_name"))
	    {
		print RENDER_OUT "$prefix$final_output";
		close(RENDER_OUT);
	    }
	    else
	    {
		WriteError("render: can't open $file_name for output. FN:$fn_var TN:$tn_var Template:$template_name");
		# Don't exit. The next iteration might be ok.
	    }
	}
    }
}

1;
