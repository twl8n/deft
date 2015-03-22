
# Due to the need for $$vars to be essentially global, package and package vars don't work. This can't be a
# package.

# package deftish;

# Exporter must be in @ISA. Dynaloader seems to be optional.
@ISA = qw(Exporter);

# subs we export by default
@EXPORT = qw(unwind clone read_tab_data newc init hr);

# Subs we will export if asked. 
#@EXPORT_OK = qw();

# The "use" statement and $VERSION seem to be required.
use vars qw($VERSION);

$VERSION = '1';

# Using $#table works if we loop by decrementing, even if we are adding rows with push() inside the loop.

# We're decrementing so that dclone() can add new rows at the end of the list and won't effect rows which
# haven't been unwound. It's clever.

my @table;
my $rowc; # Set in unwind()
my $hr;

# Scope is disabled because I can't figure out how to copy/overwrite a level of scope in keep().
# What is scope? Only for subroutines? (Apparently only for subs since it isn't used in the demo.)
my $scope = 0;

# Goodies used by runt which is dcc, emit, get_bpath, and keystr.

use Storable qw(freeze thaw);
my $distinct;
my @sort;
my %sort_vals;
my %sort_ties;
my $newvar;
my $where_eval;

use strict;

# Storable works with our list of lists. Note the function is called dclone().
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

# The Clone module works with our lists of lists and may be faster than Storable.
# use Clone qw(clone);

sub rowc
{
    return $rowc;
}

sub hr
{
    return $hr;
}

sub init
{
    # Initialize the table with 1 row and a single column. We aren't using $scope yet. It is only used for
    # subroutine stack depth.  Streams have become meaningless, since any column could be a predicate, but
    # we'll go with a default column _stream for now. Everything about Deft assumes at least 1 row, but makes
    # no assumptions about existence of any columns.

    # $table[0][$scope] = {_stream => ''};
    # $table[0][$scope] = {};
    $table[0] = {};
}

# I guess $rowc is a global. Should this be inside unwind()?
sub clone
{
    my $newr = dclone(\%{$table[$rowc]});
    push(@table, $newr);
    # return \%{$table[$#table][$scope]};
    return \%{$table[$#table]};
}

sub newc
{
    foreach my $newcol (@_)
    {
        $hr->{$newcol} = '';
    }
}

sub keep
{
    # The first arg must be a function ref, and we'll shift it off so we can pass the rest of the arg list to
    # $fref. This is probably both dangerous and powerful.
    my $fref = shift(@_);
    
    my @new;

    # Make $row local to unwind() so that recursion works. 
    my $row = $#table;

    if ($row < 0)
    {
        $row = 0;
        # $table[$row][$scope] = {} ;
        $table[$row] = {} ;
    }
    # Yes, the initializer is an empty statement
    for (  ; $row >= 0; $row--)
    {
        $rowc = $row;
        # $hr = $table[$row][$scope];
        $hr = $table[$row];
        {
            # If we use $::var here and our $var back in main, then there are no issues with strict refs or
            # use strict. To do that we need to use eval() instead of $$key.

            foreach my $key (keys(%{$hr}))
            {
                # We could undef $hr->{$key} so that we can later detect use of set_eenv() in &$fref().
                # $$key = $hr->{$key};
                eval("\$::$key = \$hr->{$key};");
            }
            # If &$fref() then keep by pushing onto the new table.
            my $test = &$fref(@_);
            # print "test: $test $::_d_order == $::test_counter && $::_d_edge eq $::_d_state\n";
            if ($test)
            {
                # $new[$new_row][$scope] = $hr;
                # $new_row++;
                push(@new, $hr);
            }
        }
    }
    if (scalar(@new))
    {
        @table = @new;
    }
}

sub delete
{
    # The first arg must be a function ref, and we'll shift it off so we can pass the rest of the arg list to
    # $fref. This is probably both dangerous and powerful.
    my $fref = shift(@_);
    
    # Make $row local to unwind() so that recursion works. 

    my $row = $#table;

    if ($row < 0)
    {
        $row = 0;
        # $table[$row][$scope] = {} ;
        $table[$row] = {} ;
    }
    # for ($row=$#table; $row >= 0; $row--)
    # Yes, the initializer is an empty statement
    for (  ; $row >= 0; $row--)
    {
        # Update the global so clone() knows which row to use.
        $rowc = $row;
        # $hr = $table[$row][$scope];
        $hr = $table[$row];
        {
            # no strict;

            # If we use $::var here and our $var back in main, then there are no issues with strict refs or
            # use strict. To do that we need to use eval() instead of $$key.

            foreach my $key (keys(%{$hr}))
            {
                # We could undef $hr->{$key} so that we can later detect use of set_eenv() in &$fref().
                # $$key = $hr->{$key};
                eval("\$::$key = \$hr->{$key};");
            }
            # If &$fref() then do not rewind, which is delete.
            if (! &$fref(@_))
            {
                foreach my $key (keys(%{$hr}))
                {
                    eval("\$hr->{$key} = \$::$key;");
                }
            }
        }
    }
}


sub unwind
{
    # The first arg must be a function ref, and we'll shift it off so we can pass the rest of the arg list to
    # $fref. This is probably both dangerous and powerful.
    my $fref = shift(@_);
    
    # Make $row local to unwind() so that recursion works. 

    my $row = $#table;

    if ($row < 0)
    {
        $row = 0;
        # $table[$row][$scope] = {} ;
        $table[$row] = {} ;
    }
    # for ($row=$#table; $row >= 0; $row--)
    # Yes, the initializer is an empty statement
    for (  ; $row >= 0; $row--)
    {
        # Update the global so clone() knows which row to use.
        $rowc = $row;
        # $hr = $table[$row][$scope];
        $hr = $table[$row];
        {
            # no strict;

            # If we use $::var here and our $var back in main, then there are no issues with strict refs or
            # use strict. To do that we need to use eval() instead of $$key.

            foreach my $key (keys(%{$hr}))
            {
                # We could undef $hr->{$key} so that we can later detect use of set_eenv() in &$fref().
                # $$key = $hr->{$key};
                eval("\$::$key = \$hr->{$key};");
            }
            &$fref(@_);
            # Where are duplicate records eliminated? 
            foreach my $key (keys(%{$hr}))
            {
                # Here we could check is defined($hr->{$key}) as a way to detect use of set_eenv() in &$fref().
                # $hr->{$key} = $$key;
                eval("\$hr->{$key} = \$::$key;");
            }
        }
    }
    
    # Create new cols in the current row, and make variables in the local scope for those columns.

    # newr({'var1' => 'value1', 'var2' => 'value2' ...})

    # This isn't really what is needed for something like read_tab_data()
    sub newr
    {
        my %args = @_;
        # Probably actually meant clone() as below, and not dclone()
        # my $newr = dclone(\@{$table[$row]});

        # clone() copies the current row, pushes it onto the end of $table[$rowc] and returns the reference of
        # the new row. We can change the new row using this new hash ref.
        my $new_hr = clone();
        foreach my $key (keys(%args))
        {
            # $newr->[$scope]->{$key} = $args{$key};
            $new_hr->{$key} = $args{$key};
        }
        # push(@table, $newr);
    }
}


# For read_tab_data() to create columns, it needs more code, and it would have to interact differently
# with unwind().

# Current read_tab_data() is perl code, that is non-aggregating and must be called inside unwind(). If it were
# aggregating code with an internal unwind loop it would also need to know about predicate/control
# columns. Maybe it is better this way, since this should behave correctly when called from inside an if() in
# an fsub.

# read_tab_data("./demo.dat", 'sequence', 'make', 'model', 'displacement','units');
# read_ws_data(...);

# Treat org mode like \s+|\s+ is the column separator
sub read_state_data
{
    my $data_file = shift(@_); # first arg is data file $_[0]
    my @va = @_; # remaining args are column names, va mnemonic for variables.
    
    my($temp);
    my @fields;
    
    # Crossmultiply the current record with a tab separated file. As written, this is non-aggregating code, so
    # it only knows about one record (the current record). It does know how to clone(), but as far as it
    # knows, there is only one record.
    
    my $log_flag = 0;

    if (! open(IN, "<",  $data_file))
    {
        if (! $log_flag)
        {
            write_log("Error: Can't open $data_file for reading");
            $log_flag = 1;
        }
        # At least in the real Deft simply exiting here leaves all the downstream ancestors hanging
        # around. rewind, don't exit.  
    }
    else
    {
        # Need to make a copy of the orig record for each input record. Either delete the orig or append one
        # of the input recs onto it.

        my $first = 1;
        while ($temp = <IN>)
        {
            my $new_hr = $hr;
            # Don't use split because Perl will truncate the returned array due to an undersireable feature
            # where arrays returned and assigned have null elements truncated.

            # Also, make sure there is a terminal \n which makes the regex both simpler and more robust.
		
            if ($temp !~ m/\n$/)
            {
                $temp .= "\n";
            }

            # Get all the fields before we start so the code below is cleaner, and we want all the line
            # splitting regex to happen here so we can swap between tab-separated, whitespace-separated, and
            # whatever.

            # Remove the leading | and whitespace. 
            $temp =~ s/^\|\s+//;

            my @fields;
            while ($temp =~ s/^(.*?)(?:\s+\|\s+)|\n)//smg)
            {
                push(@fields, $1);
            }

            print Dumper(\@fields) . "\n";

            if (! $first)
            {
                # Clone the current record, and push the clone onto the table. Since the record is cloned, we
                # only need to deal with the hash keys, and not the $$vars. unwind() won't see these cloned
                # records in this interation.

                $new_hr = clone();
                for (my $xx=0; $xx<=$#va; $xx++)
                {
                    no strict;
                    $new_hr->{$va[$xx]} = $fields[$xx];
                }
            } 
            else
            {
                # This is the actual current record, and unwind will assign the $$vars back to the hash,
                # however that back-assignment is in a loop over the keys of the hash, so we have to add the
                # hash keys and $$vars.

                $first = 0;
                for (my $xx=0; $xx<=$#va; $xx++)
                {
                    no strict;
                    $new_hr->{$va[$xx]} = $fields[$xx];
                    ${$va[$xx]} = $fields[$xx];
                }
            }
        }
    }
    close(IN);
}

# Read whitespace data
sub read_ws_data
{
    return read_data('\s+', @_);
}

sub read_tab_data
{
    return read_data('\t', @_);
}

sub read_data
{
    my $sep_regex = shift(@_); # first arg is a regex separator expression
    my $data_file = shift(@_); # second arg is data file $_[0]
    my @va = @_; # remaining args are column names, va mnemonic for variables.
    
    my($temp);
    my @fields;
    
    # Crossmultiply the current record with a tab separated file. As written, this is non-aggregating code, so
    # it only knows about one record (the current record). It does know how to clone(), but as far as it
    # knows, there is only one record.
    
    my $log_flag = 0;

    if (! open(IN, "<",  $data_file))
    {
        if (! $log_flag)
        {
            write_log("Error: Can't open $data_file for reading");
            $log_flag = 1;
        }
        # At least in the real Deft simply exiting here leaves all the downstream ancestors hanging
        # around. rewind, don't exit.  
    }
    else
    {
        # Need to make a copy of the orig record for each input record. Either delete the orig or append one
        # of the input recs onto it.

        my $first = 1;
        while ($temp = <IN>)
        {
            my $new_hr = $hr;
            # Don't use split because Perl will truncate the returned array due to an undersireable feature
            # where arrays returned and assigned have null elements truncated.

            # Also, make sure there is a terminal \n which makes the regex both simpler and more robust.
		
            if ($temp !~ m/\n$/)
            {
                $temp .= "\n";
            }

            # Get all the fields before we start so the code below is cleaner, and we want all the line
            # splitting regex to happen here so we can swap between tab-separated, whitespace-separated, and
            # whatever.

            my @fields;
            while ($temp =~ s/^(.*?)(?:$sep_regex|\n)//smg)
            {
                push(@fields, $1);
            }

            print Dumper(\@fields) . "\n";

            if (! $first)
            {
                # Clone the current record, and push the clone onto the table. Since the record is cloned, we
                # only need to deal with the hash keys, and not the $$vars. unwind() won't see these cloned
                # records in this interation.

                $new_hr = clone();
                for (my $xx=0; $xx<=$#va; $xx++)
                {
                    no strict;
                    $new_hr->{$va[$xx]} = $fields[$xx];
                }
            } 
            else
            {
                # This is the actual current record, and unwind will assign the $$vars back to the hash,
                # however that back-assignment is in a loop over the keys of the hash, so we have to add the
                # hash keys and $$vars.

                $first = 0;
                for (my $xx=0; $xx<=$#va; $xx++)
                {
                    no strict;
                    $new_hr->{$va[$xx]} = $fields[$xx];
                    ${$va[$xx]} = $fields[$xx];
                }
            }
        }
    }
    close(IN);
}

# Usage:
# value = get_eenv_handle("col",$hashref)
# It isn't a handle, but the word "ref" is already 
# in use. Used by keycmp() in runtlib.pl
sub get_eenv_handle
{
    return $_[1]->{$_[0]};
}

sub get_ref_eenv
{
    return $hr;
}

sub get_eenv
{
    return $hr->{$_[0]};
}

sub set_eenv
{
    $hr->{$_[0]} = $_[1];
}

sub slice_eenv
{
    my @val;
    # Not working. Not Array, etc errors.
    # my @val = @{$hr}{@_};
    foreach my $item (@{$_[0]})
    {
        push(@val, $hr->{$item});
    }
    return \@val;
}


# dcc() originally in runtlib.pl. dcc() is a set up wrapper for emit, so maybe we can call emit directly?
# Maybe not. At least not until we start passing functions that handle the distinct, where and sort.

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
    my $fref = sub
    {
        my $bpath = 0; # Records which fail the where, don't emit.
        
        # where eval. We are only sorting, not filtering. Could have a function ref for this.
        # Seems like a (1) would be an easy debugging shortcut.
        if (eval($where_eval)) 
        {
            my $ks_val = keystr($distinct);
            if (defined($ks_val) && exists($::exists{$ks_val}))
            {
                $bpath = $::exists{$ks_val};
                no strict;
                print "exists:$newvar gets:$hr->{$newvar} $$newvar bpath: $bpath\n";
            }
            else
            {
                $bpath = &get_bpath($ks_val);
                no strict;
                print "new:$newvar gets:$hr->{$newvar}  $$newvar bpath: $bpath\n";
            }
        }
        no strict;
        $$newvar = $bpath;
        $hr->{$newvar} = $bpath;
        # rewind(\%urh);
    };
    unwind($fref);
}

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


# sep 25 2008 fix to keep the eenv and xmult stream with table. Bug
# was that existing cols disappeared.

# Updated 2006-11-09
# Simple sub to read whitespace separated data and rewind.
# Ignores empty lines. Ignores comments. Used to read in the state table, for example states.dat

# read_ws_data("states.dat", "_d_order,_d_edge,_d_test,_d_func,_d_next");

# 0       page_search     $edit     null()          edit_page
# 1       page_search     $delete   null()          ask_delete_page
# 2       page_search     $insert   null()          edit_new_page
# 3       page_search     $item     null()          item_search
# 4       page_search     $site_gen site_gen()      next
# 5       page_search     $true     page_search()   wait
# 0       ask_del_page    $confirm  delete_page()   page_search
# 1       ask_del_page    $true     ask_del_page()  wait

# dec 29 2006 Change @va to use var args.

# See read_data() and the wrapper sub read_wd_data(). Same args, new code.
sub old_read_ws_data
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
    # my %urh;
    # while(unwind(\%urh) || $run_once)

    my $fref = sub
    {
	my $orig_eenv = get_ref_eenv();

	if (! open(RWD_IN, "< $data_file"))
	{
	    if (! $log_flag)
	    {
		write_log("Error: Can't open $data_file for reading");
		$log_flag = 1;
	    }
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
		# rewind(\%urh);
	    }
	    close(RWD_IN);
	}
    };
    unwind($fref);
}


my %_d_code_refs;

sub dispatch
{
    # Too bad I didn't leave myself a little more detail about why this is so bad.
    # die "don't use this\n";
    my $var = $_[0];

    print "dispatch: " . get_eenv($var) . "\n";
    # print "\nPress return to continue...";
    # my $var = <>;
    return;

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


1;
