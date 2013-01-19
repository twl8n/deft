#!/opt/local/bin/perl

# This is part of Deft and the DeFindIt Classic Search (dcs) engine.

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
#use DBI;
#use CGI;
#use CGI::Carp qw(fatalsToBrowser);

my($debug);
my($arrMaxIndex);
my(@allValues);
my($actionurl);

local($::soption);
local($::data_file);
local($::search_template);

sub quiet_compile_warnings
{
    #my $temp = $::DELETE_STATE_1;
    my $temp = $::dbuser;
    #$temp = $::NO_STATE;
    #$temp = $::BLANK_STATE;
    $temp = $::email_redirect;
    #$temp = $::INSERT_STATE;
    $temp = $::sql;
    $temp = $::dbpasswd;
    #$temp = $::EDIT_NEXT;
    #$temp = $::UPDATE_STATE;
    #$temp = $::CONTINUE_STATE;
    $temp = $::search_template;
    #$temp = $::NEW_STATE;
    #$temp = $::EDIT_STATE;
    $temp = $::email_subj;
    #$temp = $::DELETE_STATE_2;
    $temp = $::dbconnect;
    $temp = $::default_findme;
    #$temp = $::db;
    $temp = $::sql;
    $temp = $::dbpasswd;
    $temp = $::dbuser;
    $temp = $::email_redirect;
    $temp = $::email_subj;
    $temp = $::usedb;
    $temp = $::dbconnect;
    $temp = $::default_findme;
}

sub www_dequote
{
    my $str = $_[0];
    $str =~ s/\&amp;/\&/g;
    $str =~ s/\&quot;/\"/g;
    $str =~ s/\&apos;/\'/g;
    $str =~ s/\&gt;/\>/g;
    $str =~ s/\&lt;/\</g;
    return $str;
}

sub www_quote
{
    my $str = $_[0];
    $str =~ s/\&/\&amp\;/g;
    $str =~ s/\"/\&quot;/g;
    $str =~ s/\'/\&apos;/g;
    $str =~ s/\>/\&gt;/g;
    $str =~ s/\</\&lt;/g;
    return $str;
}
    
sub rdb_sql_core
{
    die "rdb_sql_core is no longer supported\n";
}


# sep 25 2008 fix to keep the eenv and xmult stream with table. Bug
# was that existing cols disappeared.

# Updated 2006-11-09
# Simple sub to read whitespace separated data and rewind.
# Ignores empty lines. Ignores comments.

# dec 29 2006 Change @va to use var args.

sub read_ws_data
{
    my $data_file = shift(@_); # yank off $_[0]
    my @va = @_;


    my($temp);
    my @fields;

    # Crossmultiply incoming stream with new input.
    # In other words, read the input file one time for each
    # incoming file. Take each line of the incoming file
    # and cross with the current record.

    my $log_flag = 0;
    my $run_once = 1;
    my %urh;
    while(unwind(\%urh) || $run_once)
    {
	$run_once = 0;
	my $orig_eenv = get_ref_eenv();

	if (! open(RWD_IN, "< $data_file"))
	{
	    if (! $log_flag)
	    {
		write_log("Error: Can't open $data_file for reading");
		$log_flag = 1;
	    }
	    rewind(\%urh);
	    
	    # Simply exiting here leaves all the downstream ancestors
	    # hanging around. rewind, don't exit.
	}
	else
	{
	    # Skip blank lines and comments.
	    # This doesn't have a convention for empty fields.
	    # Unlike read_tab_data() where nothing between tabs is 
	    # an empty field.
	    
	    while($temp = <RWD_IN>)
	    {
		set_ref_eenv($orig_eenv);
		if (! $temp || $temp =~ m/^\#/)
		{
		    next;
		}
		
		if ($temp !~ m/\n$/)
		{
		    $temp .= "\n";
		}
		
		# The simple regex below require the terminal \n
		# that we've added above.
		# See read_tab_data() for more notes.
		
		for(my $xx=0; $xx<=$#va && $temp; $xx++)
		{
		    $temp =~ s/(.*?)\s+//;
		    set_eenv($va[$xx], $1);
		}
		rewind(\%urh);
	    }
	    close(RWD_IN);
	}
    }
}


# sep 25 2008 fix to keep the eenv and xmult stream with table. Bug
# was that existing cols disappeared.

# Updated 2006-11-09
# Very simplistic sub to read tab separated data and rewind.
# Was sub rdb_tab_core

# dec 29 2006 Change @va to use var args.

sub read_tab_data
{
    my $data_file = shift(@_); # yank off $_[0]
    my @va = @_;

    my($temp);
    my @fields;

    # Crossmultiply incoming stream with new input.
    # Normally, there is only one incoming record.

    my $log_flag = 0;
    while(unwind())
    {
	if (! open(IN, "<",  $data_file))
	{
	    if (! $log_flag)
	    {
		write_log("Error: Can't open $data_file for reading");
		$log_flag = 1;
	    }
	    rewind();
	    
	    # Simply exiting here leaves all the downstream ancestors
	    # hanging around. rewind, don't exit.
	    #exit(1);
	}
	else
	{
	    # Need to make a copy of the orig record for each input
	    # record. Either delete the orig or append one of the
	    # input recs onto it.
	    my $first = 1;
	    while($temp = <IN>)
	    {
		# Don't use split because Perl will truncate the returned array
		# due to an undersireable feature where arrays returned and assigned
		# have null elements truncated.
		# Also, make sure there is a terminal \n which makes the regex
		# both simpler and more robust.
		
		if ($temp !~ m/\n$/)
		{
		    $temp .= "\n";
		}
		if (! $first)
		{
		    dup_insert(curr_rec());
		    set_ref_eenv(stream_head());
		}
		$first = 0;
		for(my $xx=0; $xx<=$#va && $temp; $xx++)
		{
                    # The regex needs an if() test.  If there are too few
                    # columns, the missing columns will have the value of the
                    # last column that existed. This is the old regex $1
                    # problem.

		    $temp =~ s/(.*?)[\t\n]//;
		    set_eenv($va[$xx], $1);
		}
	    }
	}
	rewind();
    }
    close(IN);
}

#
# Uses deft rewind
#
# Was a hacked dual purpose sub to read a single table database,
# or read a tab separated file.
# Those concepts were misguided.
# Instead use do_sql_simple() or read_tab_data (which
# used to be rdb_tab_core())
#
sub read_db
{
    die "read_db is no longer supported\n";
}

sub msemail
{
    #
    # we get 3 globals from msconfig()
    # email_to, email_subj, email_redirect
    #
    # We need 4 fields from the email form:
    # replyto, replyto2, message, msgsubject
    #
    my $query = new CGI();
    my %ch = $query->Vars();
    my $which_config = $_[0];
    my %vars = config($which_config);
    #init($which_config, \%ch);

    my $replyto = $ch{replyto}; # from the form
    my $safe_replyto = $replyto; # safe version of replyto
    my $replyto2 = $ch{replyto2}; # second email repeat
    my $message = $ch{message};
    my $msgsubject = $ch{msgsubject};
    my $custom = $ch{custom};
    my $safe_subj;
    #
    # I can't remember exactly what isg does, but it seems like
    # a good idea. Probably ignore case, match all chars even \n, and
    # repeat for all matches in string.
    #
    $safe_replyto =~ s/\;/semi/isg;
    $safe_replyto =~ s/\|/pipe/isg;
    $safe_replyto =~ s/\n/newl/isg;
    
    $safe_subj = "$vars{email_subj} $msgsubject"; 
    $safe_subj =~ s/\;/semi/isg;
    $safe_subj =~ s/\|/pipe/isg;
    $safe_subj =~ s/\n/newl/isg;
    chomp($safe_subj);

    my $body = "reply-to: $replyto2\nsubject: $msgsubject\ncustom: $custom\nmessage: $message\n";

    open(FILE, "| /usr/sbin/sendmail -t") || die "Couldn't pipe to sendmail\n";
    print FILE "From: $vars{email_to}\n";
    print FILE "To: $vars{email_to}\n";
    print FILE "Reply-to: $safe_replyto\n";
    print FILE "Subject: $safe_subj\n\n";   

    print FILE "$body\n";
    close(FILE);

    print "Location: $vars{email_redirect}\n\n";
}

#
# Transliterate, any non-alpha, non-digit becomes single space
# c is complement (as in negation), s is squash duplicates
#
# The string of words is split on spaces into an array of words
# since arrays are faster to deal with later when we want to step
# through the search terms.
#
# $findme =~ tr/A-Za-z0-9/ /cs;
#
sub fix_findme
{
    my $findme = $_[0];
    my $def = $_[1];
    if (length($findme) == 0)
    {
	$findme = $def;
    }
    if ($findme =~  m/\%/)
    {
	$findme = CGI::unescape($findme);
    }
    return $findme;
}

sub parse_cgi
{
    my %ch = %{$_[0]};

    # This is maybe a clever idea, but if init() isn't called exactly as expected,
    # the following loop doubles $findme
    # 
    # Use a tween so that a single instance of findme doesn't have a leading space.

    my $findme;
    my $tween; 
    for my $key (keys(%ch))
    {
	if ($key =~ m/findme/ && $ch{$key} ne "*")
	{
	    $findme .= "$tween$ch{$key}";
	    $tween = " ";
	}
    }
    return $findme;
}

sub prepare_findme
{
    my $findme = $_[0];
    my $default_findme = $_[1];

    # Too bad I didn't remind myself why "*" isn't kept in $findme.
    # This does allow for form fields findme_a, findme_b, etc.

    my $tween = "";
    if (! $findme)
    {
	$findme = $default_findme;
    }

    # This isn't foolproof.
    # It is a somewhat simpleminded escape, not true URL-encoding.

    my $findme_encoded = CGI::escape($findme);
    return ($findme, $findme_encoded);
}

# split line on space, but do quoted phrases correctly
sub split_line
{
    my $line = $_[0];
    my @findall;
    my $end = 0;
    my $start = 0;
    my $quote;
    my $term;

    # Lowercase the search string
    # Remove leading and trailing whitespace
    # Wildcards only as part of something, not as a whole term
    # (\W is non-word char)
    # The four cases are:
    # Beginning followed by \W
    # Surrounded by \W
    # Beginning followed by end
    # \W * followed by end

    $line =~ s/^\s+//; # sg makes this hang?
    $line =~ s/\s+$//; # sg makes this hang?
    $line =~ s/\s+/ /sg; # Change any single or multi whitespace to space.
    $line = lc($line);
    $line =~ s/^\*\W|\W\*\W|^\*$|\W\*$//sg;

    #<a href="http://rentawreck.serarent.com">rent a wreck</a>

    if (1)
    {
	my $long = '( |\"|\Z)';
	my $short = '(\"|\Z)'; # Noah: need regex for quoted quotes
	my $match = $long;
	while($line)
	{
	    $line =~ s/(.*?)$match//;
	    if ($1) # might have matched null string.
	    {
		push(@findall, $1);
	    }
	    if ($2 eq '"' && $match ne $short )
	    {
		$match = $short;
	    }
	    else
	    {
		$match = $long;
	    }
	}
    }
    else
    {
	# old code. Has a fix which stops infinite looping,
	# but even with the fix it is wrong.

	while( $end != -1 && $end < length($line))
	{
	    $end = index($line, ' ', $start);
	    $quote = index($line, '"', $start);
	if ($quote != -1 && $quote < $end)
	{
	    $end = index($line, '"', $end+1);
	    $end++;
	}
	if ($end <= $start) # was $end <= -1
	{
	    $end = length($line);
	}
	$term = substr($line, $start, ($end-$start));
	if ($term ne " " && $term ne '""' && $term ne "")
	{
	    push(@findall, $term);
	}
	    print "term:$term start:$start end:$end\n";
	    $end++;
	    $start = $end;
	}
    }

    # 2003-01-12 Tom:
    # Yikes! We were changing * to greedy .*, which worked until we wanted to know
    # the real number of matches. Change to non-greedy so all individual word matches
    # will be counted.
    # Remove any double quotes since we no longer need them as field separators.
    # Change plain * wild cards to .*? regular expressions.

    # Any changes here must be propogated to parseterm() so they
    # aren't excluded from the final term. 

    my $xx;
    for($xx = 0; $xx<=$#findall; $xx++)
    {
	$findall[$xx] =~ s/\"//sg;
	$findall[$xx] =~ s/\./\\\./sg; 
	$findall[$xx] =~ s/\*/\.\*\?/sg;
    }
    return @findall;
}

sub do_not_found
{
    return;
    # Add a more permanent solution to not found. Later.

    my $findme = $_[0];
    my($temp);
    my($today);
    $temp = -e $::notfound;

    if ($::soption == 1)
    {
	open(NOT_FOUND, "| $::writer_path ./ $::notfound");
    }
    else
    {
	open(NOT_FOUND, ">> $::notfound");
    }

    if ($temp == 0)
    {
	print NOT_FOUND "<html><head><title>Keywords not found</title></head>\n";
	print NOT_FOUND "<body><p>\n";
    }
    $today = `date`;
    print NOT_FOUND "$today: $findme<br>\n";
    close(NOT_FOUND);

    # We don't have a </body></html> and that is intentional
    # just to simplify this so we can append easily to the file.
    # I am pretty sure that Netscape does not care.

}

sub parseterm
{
    my $term = $_[0];
    my $firstchar = "";
    my $field = "";

    # if leading - or + remove it, and put it into $1
    # if leading field specifier (left of :) remove it and put into $field
    # if the remaining term is "", then so is everything else.

    if ($term =~ s/^(\-|\+)//s)
    {
        $firstchar = $1;
    }
    if ($term =~ s/^(.*?)\://s)
    {
        $field = $1;
    }
    if (length($term) == 0)
    {
	$firstchar = "";
	$field = "";
    }

    # Any change to the allowed char regex below
    # must match up with how terms are munged in split_line()

    $term =~ s/[^A-Za-z0-9\.\*\?]//g;
    return ($firstchar, $field, $term);
}

sub field_exists
{
    return 1;
}

sub parse_findme
{
    my @findall = @{$_[0]};
    my @def_sea = @{$_[1]};
    my %op;
    my %term;
    
    my %def_hash;
    foreach my $searchable_field (@def_sea)
    {
	$def_hash{$searchable_field} = 1;
    }
    
    # Limit searches to the first 25 tokens. (zero thru 24)

    my $max = $#findall;
    if ($max > 24)
    {
	$max = 24;
    }
    for(my $xx = 0; $xx <= $max; $xx++)
    {
	my $token = $findall[$xx];

        (my $firstchar, my $field, my $searchterm) = parseterm($token);
        if ($firstchar eq "-")
        {
            $op{$searchterm} = (-1);
        }
        elsif ($firstchar eq "+")
        {
            $op{$searchterm} = 1;
        }
        else
        {
            $op{$searchterm} = 0;
        }

	# Only search on a specific field if:
	# - the field name is non-zero length
	# - the field exists in the stream
	# - the field is in the defined searchable fields

	if (! $field )
	{
	    # It is valid not to have a specific search field. Don't warn.
	    $term{$searchterm} = "";
	}
	elsif (! field_exists($field))
	{
	    write_log("Warning: Field doesn't exist in stream:$field");
            $term{$searchterm} = "";
	}
	elsif (! $def_hash{$field})
	{
	    write_log("Warning: Field isn't in list of approved fields:$field");
            $term{$searchterm} = "";
	}
	else
        {
	    $term{$searchterm} = $field;
        }
    }
    return (\%term, \%op);
} # end parse_findme

sub op_fail($$$)
{
    my $fh_ref = $_[0];
    my $op_ref = $_[1];
    my $searchterm = $_[2];
    if ($op_ref->{$searchterm} == 1) 
    {
	#
	# + means required, 'and'
	# A required term does not exist. This record is NOT good,
	# and don't bother check other operators.
	# 
	if (! exists($fh_ref->{$searchterm}))
	{
	    # die "didn't find $searchterm\n";
	    return 1; # $final = 0;
	}

    }
    elsif ($op_ref->{$searchterm} == -1) 
    {
	#
	# - means excluded, 'nand'
	# An excluded term exists. This record is NOT good,
	# and don't bother checking other operators.
	# 
	if (exists($fh_ref->{$searchterm}))
	{
	    # die "$searchterm exists\n";
	    return 1; # $final = 0;
	}
    }
    return 0;
}

sub actionurl
{
    $actionurl = $0;
    if ($actionurl =~ m/\//s)
    {
	$actionurl =~ m/(.*?\/)+((.*?)\.pl)/;
	$actionurl = $2;
    }
    return $actionurl;
}


# If we get a match and we haven't matched this before...
# Remember, keyfound array goes with allValues array, not
# the findall array of search terms.
#
# Use regexp with leading and trailing space to assure
# full word matches
# You can't include the spaces as part of $search since then
# it won't be a regex.
#
# Space fix
# \b matches word boundaries including the implied boundary at the beginning
# and end of a string.
#
# +field:value
# -field:value
# +(type)field:value
# +value
# -value
# if (-) then found=0;
# if (!+) then found=0;
# $ op{term} = -1,0,1
# terms{field} = "searchvalue";
#
# 2004-01-02 search type used to be an arg which was passed to read_db, but
# now read_db is a deft func, so do_search will just get the appropriate data.

sub do_search
{
    my $findme_col = $_[0]; # col to search
    my $default_findme = $_[1]; # string to search for
    my $def_str = $_[2];  # ??
    my $rank = $_[3]; # name of the ranking field, aka the found record flag
    my $extras_list = $_[4]; # s, es, recordsfound

    if (! defined($rank))
    {
	write_log("do_search: rank col not defined fc:$findme_col df:$default_findme ds:$def_str\n");
	exit(1);
    }

    my @def_sea = split(',', $def_str);
    (my $s_name, my $es_name, my $rf_name) = split(',',$extras_list);
    my %foundhash;

    my $ds_key = -1; # Internal index in lieu of old record primary key field
    my %rec;
    my $pf_flag = 1;
    my $findme;
    my @findall;
    my $term_ref;
    my $op_ref;
    my %term;
    my %op;
    my $records_found = 0;
    my @def_ok;
    
    my $flag = 1;
    my %urh;
    while(unwind(\%urh))
    {
	set_eenv($rank, 0);
	undef(%foundhash);

	if ($flag)
	{
	    # Parse search string and init. For several reasons, this 
	    # needs to occur after unwinding the first record.

	    $flag = 0;
	    $findme = $default_findme;
	    if (get_eenv($findme_col))
	    {
		$findme = get_eenv($findme_col);
	    }
	    @findall = split_line($findme); 

	    # Log and exit if we asked to search a field that doesn't exist
	    # in @def_sea. This would be a development time error, and will
	    # occur during development.
	    # Returning two hashes as a 2D array munges all the hash values.
	    # "" becomes zero. Return references instead.

	    foreach my $field (@def_sea)
	    {
 		if (! exists_eenv($field))
		{
		    print ("Warning: do_search() can't search \"$field\": field is not in recordset\n");
		    foreach my $key (user_keys_eenv())
		    {
			my $value = get_eenv($key);
			print "kir:$key is $value}\n";
		    }
		}
		else
		{
		    push(@def_ok, $field);
		}
	    }
	    ($term_ref,
	     $op_ref) = parse_findme(\@findall,\@def_ok);
	    %term = %{$term_ref};
	    %op = %{$op_ref};
	}

	foreach my $searchterm (keys(%term))
	{
	    # Use while(match) in order to count the number of matches
	    # for the ranking system.

	    if ($term{$searchterm} ne "")
	    {
		my $value = get_eenv($term{$searchterm});
		while ($value =~ m/\b($searchterm)\b/ig)
		{
		    $foundhash{$searchterm}++;
		}
	    }
	    else
	    {
		# die "st:$searchterm\n";
		# try match on all fields
		foreach my $field_name (@def_ok)
		{
		    my $value = get_eenv($field_name);
		    if ($value)
		    {
			while ($value =~ m/\b($searchterm)\b/ig)
			{
			    $foundhash{$searchterm}++;
			}
		    }
		}
	    }
	}


	# Resolve the search.  + "must have" or - "must not have" can
	# make the record fail to hit.

	foreach my $searchterm (keys %op)
	{
	    if (1 == op_fail(\%foundhash, \%op, $searchterm))
	    {
		set_eenv($rank, 0);
		last;
	    }
	    elsif (exists($foundhash{$searchterm}))
	    {
		set_eenv($rank, (get_eenv($rank) + $foundhash{$searchterm}));
	    }
	}

	# Keep track of how many records we've got hits on.
	if (get_eenv($rank))
	{
	    $records_found++;
	}
	
	# If we didn't need recordsfound, s, and es we could
	# rewind each record instead of accumulating all of them.

	# Why is this a hash of hash refs instead of a list of hash
	# refs? I'm pretty sure this isn't sparce, although
	# historically it may have been sparse

	$ds_key++;
 	%{$rec{$ds_key}} = %{get_ref_eenv()};
    }

    # Search properties
    # Zero is plural in English.

    my %sp; 
    $sp{$rf_name} = $records_found;
    $sp{findme} = $findme;
    if ($sp{$rf_name} != 1)
    {
	$sp{$s_name} = "s";
	$sp{$es_name} = "es";
    }
    else
    {
	$sp{$s_name} = "";
	$sp{$es_name} = "";
    }

    # Yes, values(%rec) and not keys(%rec). We don't need the keys,
    # but the values are hash references, which are the records
    # from the input stream.
    # This will destroy $eenv{warn}, etc.

    foreach my $hr (values(%rec))
    {
	set_ref_eenv($hr);
	foreach my $sp_key (keys(%sp))
	{
	    set_eenv($sp_key, $sp{$sp_key});
	}
	rewind(\%urh);
    }
}

my %hash;
my @records;
sub ms_rewind
{
    # $_[0] better either be a hashref or undef
    if ($_[0] != undef)
    {
	# Perl is pass by reference.
	# Therefore we must copy arg zero (a ref) to a new real hash.
	my %hash = %{$_[0]};
	push(@records, \%hash);
    }
    else
    {
	push(@records, $_[0]);
    }
}

sub ms_unwind
{
    clear_eenv();
    if ($records[0] == undef)
    {
	shift(@records);
	return 0;
    }
    set_ref_eenv($records[0]);
    shift(@records);
    return 1;
}

#
# Emulate ssi virtual includes
#
sub emulate_ssi
{
    my $allFile = $_[0];
    my $pre_inc = "<!--#include virtual=\"";
    my $post_inc = "\" -->";
    my $start_inc = index($allFile, $pre_inc);
    my $start_fn;
    my $end_inc;
    my $len_fn;
    my $len_inc;

    while ($start_inc > -1)
    {
	$start_fn = $start_inc + length($pre_inc);
	$end_inc = index($allFile, $post_inc, $start_fn);
	# $len_fn = ($end_inc - length($post_inc))-$start_fn;
	$len_fn = $end_inc -$start_fn;
	$len_inc = ($end_inc + length($post_inc)) - $start_inc;
	my $inc_text;
	my $temp = substr($allFile, $start_fn, $len_fn);
	#
	# Whatever this ../ was supposed to do, it was bad. This breaks sites
	# where the SSI is in the same dirctory as the page.
	# $temp = "../$temp";
	#
	if ($temp =~ m/\.pl/)
	{
	    # Nov 06, 2002 Use standard perl path.
	    # execute perl scripts
	    # $inc_text = `/usr/bin/perl $temp`;
	    $inc_text = `/opt/local/bin/perl $temp`;
	}
	else
	{
	    # read in normal ssi files
	    my @stat_array = stat($temp);
	    my $size = $stat_array[7];
	    open(IN, "< $temp");
	    sysread(IN, $inc_text, $size);
	    close(IN);
	}
	substr($allFile, $start_inc, $len_inc) = "$inc_text<!-- $temp -->";
	$start_inc = index($allFile, $pre_inc);
    }
    return $allFile;
}


sub WriteError
{
    write_log($_[0]);
}

sub write_db
{
    if ($::usedb == 1)
    {
	# all the work happens InsertRecord, DeleteRecord, and UpdateRecord
	return; 
    }
    my %records = %{$_[0]};

    open(OUT_FILE, "| $::writer_path ./ $::data_file");

    # Write all the records out, tab separated.
    foreach my $key (keys (%records))
    {
	my $rec = join("\t", @{$records{$key}});
	print OUT_FILE "$rec\n";
    }
    close(OUT_FILE);
}



1;
