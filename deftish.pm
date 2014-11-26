
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
my $rowc = 0;
my $hr;

# What is scope? Only for subroutines? (Apparently only for subs since it isn't used in the demo.)
my $scope = 0;

use strict;

# Storable works with our list of lists. Note the function is called dclone().
use Storable qw(nstore store_fd nstore_fd freeze thaw dclone);

# The Clone module works with our lists of lists and may be faster than Storable.
# use Clone qw(clone);

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
    $table[0][$scope] = {_stream => ''};
}

# I guess $rowc is a global. Should this be inside unwind()?
sub clone
{
    my $newr = dclone(\@{$table[$rowc]});
    push(@table, $newr);
    return \%{$table[$#table][$scope]};
}

sub newc
{
    foreach my $newcol (@_)
    {
        $hr->{$newcol} = '';
    }
}


sub unwind
{
    my $fref = $_[0];
    our $row;

    for ($row=$#table; $row >= 0; $row--)
    {
        $hr = $table[$row][$scope];
        {
            no strict;
            foreach my $key (keys(%{$hr}))
            {
                $$key = $hr->{$key};
            }
            &$fref();
            foreach my $key (keys(%{$hr}))
            {
                $hr->{$key} = $$key;
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
sub read_tab_data
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

            if (! $first)
            {
                # Clone the current record, and push the clone onto the table. Since the record is cloned, we
                # only need to deal with the hash keys, and not the $$vars. unwind() won't see these cloned
                # records in this interation.
                $new_hr = clone();
                for (my $xx=0; $xx<=$#va && $temp; $xx++)
                {
                    if ($temp =~ s/(.*?)[\t\n]//)
                    {
                        no strict;
                        $new_hr->{$va[$xx]} = $1;
                    }
                    else
                    {
                        $new_hr->{$va[$xx]} = '';
                    }
                }
            } 
            else
            {
                # This is the actual current record, and unwind will assign the $$vars back to the hash,
                # however that back-assignment is in a loop over the keys of the hash, so we have to add the
                # hash keys and $$vars.
                $first = 0;
                for (my $xx=0; $xx<=$#va && $temp; $xx++)
                {
                    if ($temp =~ s/(.*?)[\t\n]//)
                    {
                        no strict;
                        $new_hr->{$va[$xx]} = $1;
                        ${$va[$xx]} = $1;
                    }
                    else
                    {
                        $new_hr->{$va[$xx]} = '';
                        ${$va[$xx]} = '';
                    }
                }
            }
        }
    }
    close(IN);
}

1;
