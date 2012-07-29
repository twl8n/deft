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
# use CGI::Carp qw(fatalsToBrowser);
# use Storable qw(nstore store_fd nstore_fd freeze thaw dclone); #fd_retrieve not exported??
use Storable qw(freeze thaw);

my $runt_err;
my @c_specs;
my @cs_order;

my $invoke; # error reporting string.

sub re
{
    #
    # I couldn't figure out how to print $runt_err from the calling script
    # so just use a function to get it. Part of the problem is that 
    # due to using msconfig.pl to create requires, the required files (logs?)
    # aren't available at compile time.
    #
    return $runt_err;
}

# Called from pull_specs()

sub offset_substring
{
    my $md_all = $_[0];      # all_template
    my $init_offset = $_[1]; # pos
    my $marker = $_[2];      # start_marker
    my $m_count = $_[3];     # start_c

    my $new_offset = $init_offset;
    my $abs_mc = abs($m_count);
    if ($m_count < 0)
    {
	$m_count = abs($m_count);
	for(my $xx = 0; $xx <= $abs_mc-1; $xx+=2)
	{
	    $new_offset = rindex($md_all, $marker, $new_offset-1);
	    if ($new_offset == -1)
	    {
		WriteError("$0:$invoke\nFatal template error: Failed to find $marker as a start marker");
		clean_db_handles();
		exit(1);
	    }
	}
	#
	# rindex finds start of substring,
	# therefore when m_count is odd, move to end of substring
	#
	if ($abs_mc % 2)
	{ 
	    $new_offset += length($marker);
	}
    }
    else
    {
	# When searching forward, start from the end of the control spec
	# Starting offset must be one position back (e.g. the zeroth position).

	$new_offset--;
	for(my $xx = 0; $xx <= $abs_mc-1; $xx+=2)
	{
	    $new_offset = index($md_all, $marker, $new_offset+1);
	    if ($new_offset == -1)
	    {
		WriteError("$0:$invoke\nFatal template error: Failed to find $marker as a start marker");
		clean_db_handles();
		exit(1);
	    }
	}
	if ($abs_mc % 2 == 0)
	{
	    $new_offset += length($marker);
	    
	}
    }
    return $new_offset;
}


# This only builds the odd nodes
# Evens are filled in later

sub build_nest_node
{
    my $hkey = $_[0];
    my %spec = %{$_[1]};
    my $nest_ref = $_[2];

    $nest_ref->{$hkey}{_agg_spec} = $spec{agg_spec};

    # Tweens are assoc. with odd array elements.
    # Is this code correct?

    $nest_ref->{$hkey}{_tweens} = ""; # $tween;
}

sub dice_template
{
    my $template = $_[0];
    my $nest_ref = $_[1];

    my @cuts;
    pop @c_specs;
    foreach my $item (@c_specs)
    {
	push @cuts, ($item->{start}, $item->{stop});
    }
    my @pieces = &make_cuts($template, @cuts);
    my $index = 0; # $root_key?
    my $key = 0;   # $root_key? placeholder?
    while (@pieces)
    {
	$nest_ref->{$key}{_chunk}[$index]= shift @pieces;
	if ($nest_ref->{$key}{_chunk}[$index+1])
	{
	    $key = $nest_ref->{$key}{_chunk}[$index+1];
	    $index = 0;
	}
	else
	{
	    if ($key =~ s/\|(\d+)$//)
	    {
		$index = $1 + 1;
	    }
	    # Don't put an else here.
	    # Don't try to print $nest_ref->{$key} here.
	    # There is no else. We're suppose to break here.
	    # Noah says: it's null because it would be trying to print
	    # the element after the last element of the list.
	}
    }
}

sub make_cuts
{
    my $text = shift @_;
    my @cut_order = sort {$a <=> $b} @_;
    my @out;
    my $item;
    my $prev = 0;
    foreach $item (@cut_order)
    {
	push(@out, substr($text, 0, $item-$prev, ''));
	$prev = $item;
    }
    push(@out, $text);
    return @out;
}

sub is_sibling
{
    my $hr = $_[0];
    my $hr_prev = $_[1];

    if (($hr->{start} >= $hr_prev->{start} &&
	 $hr->{stop} < $hr_prev->{stop}) ||
	($hr->{start} > $hr_prev->{start} &&
	 $hr->{stop} <= $hr_prev->{stop}))
    {
	return 0;
    }
    elsif (($hr->{start} >= $hr_prev->{start} &&
	    $hr->{start} < $hr_prev->{stop}) &&
	    ($hr->{stop} > $hr_prev->{stop}))
    {
	WriteError("$0:$invoke\nOverlapping loops:");
	WriteError("starts:$hr->{start}, $hr_prev->{start}\nCurr cspec:$hr->{cs}");
	WriteError("stops:$hr->{stop}, $hr_prev->{stop}\nPrev cspec:$hr_prev->{cs}");
	clean_db_handles();
	exit(1);
    }
    return 1;
}

#
# Build a data structure of the locations where we'll cut up the template
# Probably don't do the cutting here.
# 
sub create_divs
{
    my $parse_this = $_[0];
    my $cs_index;
    my $hr;
    my $hr_prev;
    my @pkey; # parent key stack
    my %nest_lookup;
    my %nest; # Where %nest is instantiated!

    # Add the root, all encompassing c_specs entry;

    my %temp;
    $temp{start} = 0;
    $temp{stop} = length($parse_this);
    push(@c_specs, \%temp);
    unshift(@cs_order, $#c_specs);

    $nest_lookup{"0"} = 0; # was ... "0"} = 0
    build_nest_node("0", $c_specs[$#c_specs], \%nest); # was zero
    $nest{"0"}{_chunk}[0] = ''; # was zero
    	
    my $back_count;
    for (my $cs_count = 1; $cs_count <= $#cs_order; $cs_count++)
    {
	$back_count = 1;
	$cs_index = $cs_order[$cs_count];
	$hr = $c_specs[$cs_index];
	$hr_prev = $c_specs[$cs_order[$cs_count-$back_count]];

	while(is_sibling($hr, $hr_prev))
	{
	    $back_count++;
	    $hr_prev = $c_specs[$cs_order[$cs_count-$back_count]];
	}

	my $nl_temp = $cs_count-$back_count;
	my $parent_key = $nest_lookup{$nl_temp};
	my $pk_size = $#{$nest{$parent_key}{_chunk}}+1;
	my $hkey = "$parent_key|$pk_size";

	# Each child adds two elements to a parent array.
	# Push a two element array here.

	push(@{$nest{$parent_key}{_chunk}}, ($hkey,'')); 
	$nest{$hkey}{_chunk}[0]='';

	build_nest_node($hkey,  $c_specs[$cs_index], \%nest);
	$nest_lookup{$cs_count} = $hkey;
    }

    # dice_template() changes the %nest reference in place.

    dice_template($parse_this, \%nest);

    return \%nest;
}

sub parse_nest
{
    my $n_key = $_[0];
    my $nest_ref = $_[1];

    my $xx;
    # print "pn: $n_key\n";
    my @narr = @{$nest_ref->{"$n_key"}{_chunk}};
    
    for($xx=0; $xx <= $#narr; $xx++)
    {
	if ($xx % 2) # odd
	{
	    parse_nest("$narr[$xx]", $nest_ref);
	}
	else # even
	{
	    write_log("key:$n_key\[$xx\]\n");
	    if ($n_key ne 't')
	    {
		# _add_spec is null for root.
		# In the old days we printed _agg_where_eval which is concated
		# and therefore coincidently wasn't null.

		write_log("$nest_ref->{$n_key}{_agg_spec}\n");
	    }
	    write_log("$narr[$xx]\n\n");
	}
    }
}

#
# Check and parse both at the same time
# {$var start str -n stop str2 +n}
#
sub check_cstring
{
    my $cstring = $_[0];
    my $orig = $cstring;
    my $start_marker = "";
    my $start_c = "";
    my $end_marker = "";
    my $end_c = "";
    
    
    #
    # control vars must begin with a letter.
    #
    my $aggregate_spec;
    if ($cstring =~ s/\{\s*\$([a-zA-Z][a-zA-Z0-9_]*)//s)
    {
	$aggregate_spec = $1;
    }
    else
    {
	$runt_err .= "Syntax error: Didn't find control, or control is missing \$var.\n";
    }

    if ($cstring =~ s/start\s+(.*?)\s+([\-+]\d+)\s+//s)
    {
	$start_marker = $1;
 	$start_c = $2;
	$start_marker =~ s/(?<!\\)&lt;/</sg;
	$start_marker =~ s/(?<!\\)&gt;/>/sg;
	$start_marker =~ s/\\(\d+)/chr($1)/eg;
	#  s/\\([0-9]{3})/chr(oct($1))/eg;
	$start_marker =~ s/\\(.)/$1/sg; 
    }
    else
    {
	$runt_err .= "Syntax error: Missing start.\n";
    }
    if ($cstring =~ s/stop\s+(.*?)\s+([\-+]\d+)\s*//s)
    {
	$end_marker = $1;
	$end_c = $2;
	$end_marker =~ s/(?<!\\)&lt;/</sg;
	$end_marker =~ s/(?<!\\)&gt;/>/sg;
	#  s/\\([0-9]{3})/chr(oct($1))/eg;
	$end_marker =~ s/\\(\d+)/chr($1)/eg;
	$end_marker =~ s/\\(.)/$1/sg; 
    }
    else
    {
	$runt_err .= "Syntax error: Missing stop:$cstring\n";
    }
    
    # 
    # When we do tweens, they'll go at the end of the cspec
    # and get parsed down here somewhere.
    #
    if ($cstring !~ s/\s*\}//s)
    {
	$runt_err .= "Syntax error: control spec is not \} terminated.\n";
    }
    
    if (0 < length($cstring))
    {
	my $temp = $cstring;
	$temp =~ s/(.)/sprintf("\\%3.3o",ord($1))/seg;
	$runt_err .= "Syntax error: unrecognized text at the end: $cstring ($temp)\n";
    }
    if (0)
    {   # Debugging. Typical good,results look like:
	#cs:{$distinct_faq_pk start &lt;tr -2 stop &lt;/tr&gt; +4}
	#re:
	#sm:<tr
	#sc:-2
	#em:</tr>
	#ec:+4
	#as:distinct_faq_pk
	
	my $temp = sprintf("cs:%s\nre:%s\nsm:%s\nsc:%s\nem:%s\nec:%s\nas:%s\n",
			   $orig,
			   $runt_err,
			   $start_marker,
			   $start_c,
			   $end_marker,
			   $end_c,
			   $aggregate_spec);
	WriteError("$temp");
    }
    
    if ($runt_err)
    {
	return (0,
		$aggregate_spec,
		$start_marker,
		$start_c,
		$end_marker,
		$end_c);
    }
    else
    {
	return (1,
		$aggregate_spec,
		$start_marker,
		$start_c,
		$end_marker,
		$end_c);
    }
}


sub pull_cspecs
{
    my $all_template = $_[0];
    my $xx = 0;
    undef(@c_specs);
    undef(@cs_order);
    my @cs_unorder; # two d array

    my $start_cut = 0;
    my $new_template;
    # 
    # zero width, backward looking, negative assertion, looking for \
    # pos() is the end of the match.
    # 
    while($all_template =~ m/({.*?(?<!:\\)})/sg)
    {
	$c_specs[$xx]{cs} = $1;
	$c_specs[$xx]{pos} = pos($all_template) - length($c_specs[$xx]{cs});

	pos($all_template) = 0;
	if ( $all_template !~ s/({.*?(?<!:\\)})//s)
	{
	    WriteError("s didn't match");
	    exit();
	}
	$xx++;
	if ((0) && ($xx > 10)) #this should be meaningless
	{
	    # this may require adjustment or even elimination if the number of 
	    # loop constructions in a template grows too large
	    write_log("cspec parse error:$1");
	    exit();
	}
    }
    
    #
    # Why was this init to 1??
    #
    for(my $yy = 0; $yy <= $#c_specs; $yy++)
    {
	(my $ok_flag,
	 $c_specs[$yy]{agg_spec},
	 $c_specs[$yy]{start_marker},
	 $c_specs[$yy]{start_c},
	 $c_specs[$yy]{end_marker},
	 $c_specs[$yy]{end_c}) = check_cstring($c_specs[$yy]{cs});
	if (! $ok_flag)
	{
	    return "";
	}
	$c_specs[$yy]{start} = offset_substring($all_template,
						$c_specs[$yy]{pos},
						$c_specs[$yy]{start_marker},
						$c_specs[$yy]{start_c});
	$c_specs[$yy]{stop} = offset_substring($all_template,
					       $c_specs[$yy]{pos},
					       $c_specs[$yy]{end_marker},
					       $c_specs[$yy]{end_c} );

	@{$cs_unorder[$yy]} = ($c_specs[$yy]{start},$yy);
    }
    #
    # Sort the unordered start positions. Do this instead of using the hash that Noah
    # advised against, and which contained integer keys (which was bad for identical starting 
    # positions).
    # @cs_order will be contain the sorted starting positions.
    # Convert the sorted start positions to indices into @c_spec.
    # 
    my @cs_o_temp = sort {$a->[0] <=> $b->[0]} @cs_unorder;
    for(my $zz = 0; $zz <= $#cs_o_temp; $zz++)
    {
	$cs_order[$zz] = $cs_o_temp[$zz][1];
    }

    return $all_template;
}

# Ask Noah about this.
sub convert_nest
{
    my $nest_ref = $_[0];

    foreach my $item (keys(%{$nest_ref}))
    {
	my $new_key = $item;
	if ($new_key =~ s/(\d+)/('t' x ($1+1))/eg)
	{
	    $nest_ref->{$new_key} = $nest_ref->{$item};
	    delete($nest_ref->{$item});
	    foreach my $ii (0..$#{$nest_ref->{$new_key}{_chunk}})
	    {
		if ($ii % 2) # odd
		{
		    $nest_ref->{$new_key}{_chunk}[$ii]  =~ s/(\d+)/('t' x ($1+1))/eg;
		}
	    }
	}
    }
}

sub compile_core
{
    my $in_filename = $_[0];

    my $alltxt;
    my @stat_array = stat($in_filename);
    my $size = $stat_array[7];
    if (! open(IN, "< $in_filename"))
    {
	my $pwd = `/bin/pwd`;
	chomp($pwd);
	WriteError("runt->compile: can't open $in_filename for read. pwd:$pwd");
	exit(1);
    }
    sysread(IN, $alltxt, $size);
    close(IN);

    # At this point only {value_xx} is allowed inside "" in the HTML.
    $alltxt =~ s/%7B(value_[0-9]*)%7D/{$1}/sig;

    $alltxt = pull_cspecs($alltxt);
    my $re = re();
    if ($re)
    {
	write_log("$0: Template compile error for $in_filename:\n$re");
	# warn("Template compile error for $in_filename:\n$re");
	clean_db_handles();
	exit(1);
    }

    # %nest originates in create_divs().
    # Passed by reference and changed in convert_nest().

    my $nest_ref = create_divs($alltxt);
    convert_nest($nest_ref);

    # Uncomment this to get %nest printed into the log
    # parse_nest('t', $nest_ref);


    # Nest has some other stuff in it, since we can only freeze a single hash into a file 
    # (or at least that's what I think).
    # $nest_ref->{key}{stuff} where {stuff} is _chunk, _agg_spec, _tweens

    my $frozen = freeze($nest_ref);

    return ($frozen, $stat_array[9], $nest_ref); # [9] is mtime
}


# Called below, and from runt.pl:render()

sub db_runt_name
{
    my $hostname = `/bin/hostname`;
    chomp($hostname);
    return "$hostname\:$_[0]";
}


# save compiled template to the db.
sub compile_db
{
    my $in_filename = $_[0];
    my $te_pk = $_[1];

    $invoke = "in:$in_filename out:database";

    # $frozen is a reference returned from freeze().
    # $te_epoch is the last mod time in seconds of the template file.

    (my $frozen, my $te_epoch, my $nest_ref) = compile_core($in_filename);

    my $db_runt_name = db_runt_name($in_filename);

    if ($te_pk)
    {
	sql_update_template($frozen, $te_epoch, $te_pk);
    }
    else
    {
	sql_insert_template($db_runt_name, $frozen, $te_epoch);
    }
    return $nest_ref;
}

# Fix the original file name with a path as necessary, then
# create a rnt name. Return both names.

sub munge_fn
{
    my $name = $_[0];
    my $fixed;

    if ($name !~ m/\//)
    {
	# If no path, force path to be same as the script.
	$name = "$FindBin::Bin/$name";
    }

    $name =~ m/(.*)\/(.*)\./;
    $fixed = "$1/$2\.rnt";

    return ($name, $fixed);
}

# Save the compiled template to a file, and return the nest reference.
sub compile_rnt
{
    my %arg = @_;
    my $in_file = $arg{in_file};
    my $out_file = $arg{out_file};

    $invoke = "in:$in_file out:$out_file";

    (my $frozen, my $te_epoch, my $nest_ref) = compile_core($in_file);

    if (! open(OUT, "> $out_file"))
    {
	WriteError("runt_compile.pl compile(): $@\ncan't open $out_file for output\n");
	exit(1);
    }
    print OUT $frozen;
    close(OUT);
    return $nest_ref;
}

1;
