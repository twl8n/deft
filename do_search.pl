#
# define variables named $Default_findme $Def_str and $Rank
#
sub do_deft_search
{
    $$Rank = 0;
    unless ($findme) 
    {
	$findme = $Default_findme;
    }
    $findme =~ s/^\s*(.*?)\s*/$1/s;
    lc($findme);
    $findme =~ s/^\*\W|\W\*\W|^\*$|\W\*$//sg;
    duc(Marker);
    $records_found = 1;
    naive_make_col('findall', '', 'findall($findme)');
    naive_make_col('def_sea', '',"split(',',\$Def_str)");

    #
    # Log and exit if we asked to search a field that doesn't exist
    # in @def_sea. This would be a development time error, and will
    # occur during development.
    # Returning two hashes as a 2D array munges all the hash values.
    # "" becomes zero. Return references instead.
    # 
        
    if (!(exists($$def_sea))) 
    {
	write_log("Warning: do_search() can't search \"$field\": field is not in recordset");
	exit;
    }
    ( $firstchar, $field,  $searchterm) = parseterm($findall);
    if ($firstchar eq "-")
    {
	$op = (-1);
    }
    elsif ($firstchar eq "+")
    {
	$op = 1;
    }
    else
    {
	$op = 0;
    }
    #
    # Only search on a specific field if:
    # - the field name is non-zero length
    # - the field exists in the stream
    # - the field is in the defined searchable fields
    #
    
    if (! $field )
    {
	# It is valid not to have a specific search field. Don't warn.
	$term = "";
    } 
    elsif (! exisit($$field)) 
    {
	write_log("Warning: Field doesn't exist in stream:$field");
	$term = "";
    } 
    else
    {
	$term = $field;
    }
    if ($term ne '') 
    {
	while ($$term =~ m/\b$searchterm\b/ig)
	{
	    $found++;
	}
    }
    else 
    {
	if ($$def_sea) 
	{
	    while ($$def_sea =~ m/\b$searchterm\b/ig)
	    {
		$found++;
	    }
	}
    }
    if (($op == 1) && !($found)) 
    {
	# required field unfound
	$$Rank = 'failed';
    } elsif ($found)
    {
	$$Rank = $found;
    }
    # agg to get field list
    crush_on('do_search_sum','Marker',"$Rank, record_found");
    if ($records_found != 1)
    {
	$sps = 's';
	$spes = 'es';
    }
}

sub do_search_sum
{
    my $sum = 0;
    foreach my $item (@_) 
    {
	if ($item !~ /^\d*$/) 
	{
	    return 0;
	}
	$sum += $item;
    }
}

sub build_findall
{
    while( $end != -1 && $end < length($line))
    {
        $end = index($line, ' ', $start);
        $quote = index($line, '"', $start);
        if ($quote != -1 && $quote < $end)
        {
            $end = index($line, '"', $end+1);
            $end++;
        }
        if ($end == -1) { $end = length($line); }
        $term = substr($line, $start, ($end-$start));
        if ($term ne " " && $term ne '""' && $term ne "")
        {
            push(@findall, $term);
        }
        $end++;
        $start = $end;
    }
    return (@findall);
}
