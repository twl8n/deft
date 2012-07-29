#my @streams; # list (stream_id) of lists (records) of hashes (columns)
#my @union_stack; # list of stream_id to join later.
#my $rec_avail;
#my $unwind_index = 0;
#my $rewind_index = 0;
#my @record_set;

#my $out_stream_counter = 0;
#my @stack;


# Check the stack. If the top stream has no records then it isn't ok.
# We don't want to process it, but we need to leave it on the stack,
# since if we (hypothetically) did process it, we would also 
# create a new stream on top of the stack with next_stack(), and this new
# stream would be the output stream. 

# sub stream_ok
# {
#     my $sid = read_stack(0);
#     my $stream_size = $#{$streams[$sid]};

#     if ($stream_size >= 0)
#     {
# 	my $ret_stream = pop_stack();
# 	# debug
# 	#print "stream $sid is ok. Returning:$ret_stream\n";
# 	return $ret_stream;
#     }
#     else
#     {
# 	# debug
# 	#print "stream $sid is not ok. Don't pop. Return:undef\n";
# 	return undef;
#     }
# }

# sub next_stream
# {
#     $out_stream_counter++;
#     return $out_stream_counter;
# }

# sub next_stack
# {
#     # Normally there is no "next" stack since recs are processed in
#     # place.  If there is anything to do here, we'll need set the
#     # stream head, maybe calling reset_stream() or something.

#     # $out_stream_counter++;
#     # push(@stack, $out_stream_counter); return
#     # $out_stream_counter;
# }

# sub pop_stack
# {
#     return pop(@stack);
# }

# sub swap_stack
# {
#     die "swap_stack deprecated\n";

#     my $sti = $#stack;
#     my $first_element = $stack[$sti];
#     my $second_element = $stack[$sti-1];
#     $stack[$sti] = $second_element;
#     $stack[$sti-1] = $first_element;
#     #print "sti:$sti $first_element swapped with $second_element\n";
# }

# sub read_stack
# {
#     return $stack[$#stack-$_[0]];
# }

# my @multi_stack;
# sub push_multi
# {
#     push(@multi_stack, pop_stack());
# }

# sub join_multi
# {
#     my $dest = read_stack();
#     while(my $orig = pop(@multi_stack))
#     {
# 	foreach my $hr (@{$streams[$orig]})
# 	{
# 	    push(@{$streams[$dest]}, $hr);
# 	}
#     }
# }

# sub stream_size
# {
#     return $#{$streams[$_[0]]};
# }


# sub new_union
# {
#     push(@union_stack, -1);

#     # debug
#     #my $var = join(', ', @union_stack);
#     #print "nu:$var\n";
# }

# If the stack has more than at least 1 element, pop off
# and push on to @union_stack.
# Wrong: We can leave @stack empty assuming union_stack() will follow next.

# sub pop_to_union
# {
#     my $sti = $#stack;
#     if ($sti > 0)
#     {
# 	my $sid = pop_stack();
# 	push(@union_stack, $sid);
	
# 	# debug
# 	#print "popping $sid to union stack\n";
#     }
#     else
#     {
# 	die "Cannot pop stack:$stack[$#stack] to union stack. Would create empty stack.\n";
#     }
# }


# If the join stack has more than one
# The new combined stream is the same as the top
# of the union_stack. Push the orig onto the real stream stack
# and this will be our record destination.
# Join all the records from everything to the records of the destination.
# sub union_streams
# {
#     #my $utag = join(',',@union_stack);
#     #my $stag = join(',',@stack);
#     #print "u:$utag s:$stag\n";

#     # union stack index
#     my $usi = $#union_stack;

#     if ($usi >= 0)
#     {
# 	# We do not allow a null stream stack, so no need to check
# 	# if the stream stack has something. It always has at least one element.

# 	my $dest = $stack[$#stack];
	
# 	# As far as I know, there is no way this code will ever run.
# 	# pop_to_union() won't allow a null stream stack.
	
# 	if (! defined($dest))
# 	{
# 	    die "No stream on stack. union_streams() cannot continue.\n";
# 	}

# 	# Only pop from the union stack until we hit a -1 
# 	# which marks a code block boundary. See new_union() above.
# 	# This block boundary method is crude, but seems robust.
	
# 	while( my $orig = pop(@union_stack))
# 	{
# 	    if ($orig == -1)
# 	    {
# 		last;
# 	    }
# 	    my $tag = join(',',@stack);
# 	    #print "Unioning $orig to $dest (tag:$tag)\n";
# 	    foreach my $hr (@{$streams[$orig]})
# 	    {
# 		push(@{$streams[$dest]}, $hr);
# 	    }
# 	}
#     }
#     else # if ($usi < 0)
#     {

# 	# Neither the union_stack nor the stream stack should ever be
# 	# empty.

# 	die "union_stack is empty. stmax:$#stack stack top:$stack[$#stack]\n";
#     }
# }

# sub debug_stacks
# {
#     printf("$_[0] in:$::in_stream stack:%s union stack:%s\n", join(",", @stack), join(",", @union_stack));
# }

# Note A:
# Compiling results in a reference to a hash of lists
# of eval-ready code strings.
#
# Note B:
# Assume eenv is already initialized. 
# Make any updates to eenv, then rewind so there is one starting record
# in the stream.
# 
# Save state info e.g. next node 
# Put into eenv for rendering since it needs to go into templates.

# sub run_core
# {
#     my $all_lines = $_[0];
#     my $to_node_fk = $_[1];

#     # See note A above.
#     $::exec = compile_deft($all_lines);

#     foreach my $language (keys(%{$::exec})) 
#     {
# 	if ($language ne 'deft')
# 	{
# 	    if ($language eq 'perl')
# 	    {
# 		foreach my $import_sub (keys(%{$::exec->{$language}}))
# 		{
# 		    eval($import_sub);
# 		}
# 	    }
# 	}
#     }
#     # See note B above.
#     if (defined($to_node_fk))
#     {
# 	set_eenv("next_node", $to_node_fk)
#     }

#     #set_eenv("_test", 10);
#     set_eenv("_return", 1);

#     # init the context (code, in, out, last)
#     # The top node needs a non-zero output stream.
#     my $top_out = next_stream();
#     set_context("", 0, $top_out, $top_out);

#     # each new 'process' onto bottom of context stack.
#     my $top_in = spawn_processes($::exec->{deft}{main}); 

#     # rewind to top stream's in.
#     $::out_stream = $top_in;

#     rewind();

#     # Note 2:
#     # Need to make no strict for the eval so $$vars will work.
#     # The perlfunc man page says that $@ won't work for everything. 
#     # All code is turned into Deftish Perl at compile.

#     while(pop_context())
#     {
# 	(my $code,
# 	 $::in_stream,
# 	 $::out_stream,
# 	 my $last) = read_context();
	
# 	# die "i:$::in_stream o:$::out_stream l:$last\n";

# 	# See note 2 above.
# 	{
# 	    no strict;
# 	    # print "|$code|\n";
# 	    eval($code);
# 	    if ($@)
# 	    {
# 		die "$@\nst_lib.pl err:$code\n";
# 	    }
# 	} 
#     }
    
#     #
#     # We should stop crushing the final stream. The final stream
#     # was rewound to stream zero, making it ready for the next script.
#     # (If there is a next script.)
#     # 
#     return get_eenv("_return");
# }
# rw2: Allowing different columns in records is evil [later note:
# perhaps not it shouldn't cause trouble, although it only happens
# with a union, and union is very rare].  It becomes necessary to
# un-restorevars after rewind since the next record may have different
# columns and may not therefore be able to undef existing
# columns. Leaving the columns around gives the impression that this
# record has the same value for non-existant columns as the previous
# record.

# rw3: Compiled code doesn't use restorevars() so we don't need the stupid
# cleaning code. So, once all uses of restorevars() are followed by
# postusevars(), rewind() can be simplified.

# rw4: $old_eenv will not exist if the input stream has no records.
# This will (often?) be the case for the first line of code. 
# After that, it will be fairly unusual since this case would require
# deleting all the records. 

# @streams is list of lists of hash references
# $stream[x] is a list of the records (hash refs) in stream x.

# See common_lib.pl:patch_eenv()
# We need an old-style simple rewind to call from patch_eenv()
# after it has patched a record.

# This is not used by the new, simple rewind() and unwind().
# See the subs noah*wind below.

# Called from patch_eenv() in common_lib.pl. Probably not used by new
# memoize pass.

# sub pe_rewind 
# {
#     my $urh = $_[0];
    
#     my $out_stream = $urh->{out_stream};

# #     my @var_list = sys_keys_eenv();
# #     my $v_str = join(',', @var_list);
# #     my $rewind_key = slice_key(\@var_list);
    
#     my $rewind_key = raw_key();
#     if (! exists($urh->{$rewind_key}))
#     {
# 	print "    pe rewinding($::out_stream):$rewind_key\n";
# 	push(@{$streams[$::out_stream]}, get_ref_eenv());

# 	# Just a guess that we want to push get_ref_eenv() as initial value.
# 	push(@{$urh->{$rewind_key}}, get_ref_eenv());
#     }
#     else
#     {
# 	print "pe not rewinding($::out_stream):$rewind_key\n";
#     }
#     postusevars(); 
#     clear_eenv();
# }

# # complex, distinct-on unwind

# my $rw_ok = 1;
# sub rewind_ok
# {
#     $rw_ok = 1;
# }

# sub wrong_think_memoizing_unwind
# {
#     my $urh = $_[0];
    
#     # We must have a view list. of the calling code
#     # didn't supply one, use all the columns.
#     if (! $urh->{view_list})
#     {
# 	# print "uw sets view list for out_stream $::out_stream\n";
# 	my @var_list = sys_keys_eenv();
# 	$urh->{view_list} = \@var_list;
#     }    
    
#     my $result = 0;
#     while(my $eeref = pop(@{$streams[$::in_stream]}))
#     {
# 	$result = 1;
# 	set_ref_eenv($eeref);
# 	$urh->{view_key} = slice_key($urh->{view_list});
	
# 	# print "unwind vk:$urh->{view_key}\n";
# 	# Does $urh have a key $urh->{view_key} ? Funny looking syntax.
# 	if (exists($urh->{$urh->{view_key}}))
# 	{
# 	    #print "patching with exists-view_key:$urh->{view_key} val:$urh->{$urh->{view_key}}\n";
# 	    #use Data::Dumper;
# 	    #printf("dump:%s\n", Dumper($urh));
# 	    patch_eenv($urh);
# 	}
# 	else
# 	{
# 	    # overwrite value for key old_eenv for each record.
# 	    $urh->{old_eenv} = local_eenv($urh->{view_list});
# 	    last;
# 	    printf("old_eenv:%s !exists:%s vk:$urh->{view_key} view_list:$urh->{view_list}\n",
# 		   local_eenv($urh->{view_list}),
# 		   $urh->{$urh->{view_key}});
# 	}
#     }
#     # Success unwinding is true. The first time we unwind, we pretend
#     # it was true so that the while loop will run at least once. After that
#     # we will try to unwind at least once only if the prior call to rewind
#     # put at least one record in the output stream.
    
#     if ($uw_flag)
#     {
# 	$result = 1;
# 	$uw_flag = 0;
#     }

#     if (! $result)
#     {
# 	if ($rw_ok)
# 	{
# 	    # Previous rewind was ok, but we didn't unwind anything,
# 	    # so the rewind is not ok unless rewind resets it. This
# 	    # determines whether or not we exit when unwind was not
# 	    # successful.

# 	    $rw_ok = 0;
# 	}
# 	elsif ($::in_stream > 1)
# 	{
# 	    # sep 26 2008 Not such a good idea. Maybe exit if there are no
# 	    # other streams on the stack.

# 	    #print "No data in stream $::in_stream. Exiting.\n";
# 	    #exit(1);
# 	}
#     }
#     return $result;
# }


# sub rewind_simple
# {
#     push(@{$streams[$::out_stream]}, get_ref_eenv());
# }


# See comments in docs/implementation.txt
# SQL-style, simple unwind.
# Remove duplicates in the rewind stage.

# sub unwind_simple
# {
#     if (my $eeref = pop(@{$streams[$::in_stream]}))
#     {
# 	set_ref_eenv($eeref);
# 	return 1;
#     }
#     else
#     {
# 	return 0;
#     }
# }


# Not used, but is Noah's original model.
# diff_eenv() and patch_eenv() are in common_lib.pl
# unwind_full() is not used, but did server as the model
# for what the compiler does.

# sub unwind_full
# {
#     my $populate = '';
#     my $gather = '';
    
#     #in this version $rval will be replaced by $populate and $gather
#     #each contain an eval'able code string. $populate creates
#     #the namespace appropriate to execution of the code
#     #$gather records the data appropriate to rewind
    
#     my $eeref;
#     if (!($eeref = pop(@{$streams[$::in_stream]})))
#     {
# 	return (0);
# 	#end condition
#     }

#     #we have a reference to the environment now and then we
#     #need to determin whether we have a restriction on the stream
    
#     #code ref needs to be passed to all instances of unwind_all it must be unique
#     #for a given input stream (its posible this will be tricky)
#     my $code_ref = shift @_;
    
#     if (@_)
#     {
# 	#this takes a list of variable name translation pairs
# 	#if the set has been seen before then the row should be 
# 	#patched and immediatly rewound the convention \var_name
# 	#shall be understood to mean the variable is mutable
# 	#otherwise enforcing immutability is appropriate
# 	#exporting of variable into the namespace from here is also
# 	#to be prefered to other methods though not as globals
# 	my @args;
# 	while ( @_ )
# 	{
# 	    push @args ,join('|',splice @_, 0, 2);
# 	}
# 	my @vars = map {s/^\///} grep {/^\//} @args;
# 	my @constants = grep {/^[^\/]/} @args;
# 	my @view;
# 	foreach my $pair (@vars)
# 	{
# 	    my @map = split(/|/,$pair);
# 	    $populate .= "my \$$map[1] = \&get_eenv($map[0]);\n";
# 	    $gather .= "&set_eenv($map[0],\$$map[1]);\nundef(\$$map[1]);\n";
# 	    push @view, $map[0];
# 	}

# 	foreach my $pair (@constants)
# 	{
# 	    my @map = split(/|/,$pair);
# 	    $populate .= "my \$$map[1] = \&get_eenv($map[0]);\n";
	    
# 	    #this is where we should do error capture for attempted 
# 	    #mutation on constants

# 	    $gather .= "undef(\$$map[1]);\n";
# 	    push @view, $map[0];
# 	}
# 	&set_ref_eenv($eeref);

# 	#I'll need two more utility functions on hash refs these belong in 
# 	#common_lib but I'll define them below. I need to do the shortcutting
# 	#here the tricky bit is this needs to keep working if we change execution
# 	#styles in st to allow multiple unwinds to be running simultaneously
	
# 	my $view_key = join(' ,',@{&slice_eenv(@view)});
# 	if (exists($::mem_cache{$code_ref}{$view_key}))
# 	{
# 	    &patch_eenv(@{$::mem_cache{$code_ref}{$view_key}});
# 	}
# 	else
# 	{
# 	    $gather = "
# my \$comp_ref = &get_env_ref;
# $gather;
# push @{ \$::mem_cache{$code_ref}{$view_key} }, &diff_eenv(\$comp_ref);
# &rewind;";
# 	}
#     }
#     else
#     {
# 	# Noah: Disgusting but necessary for full support of inlined
# 	# dynamic code also used in some internal functions
# 	# Tom: I don't think so. Internal functions call get_eenv() and
# 	# set_eenv() and I don't think they support inline code in the normal sense.

# 	set_ref_eenv($eeref);
# 	$populate = '&restorevars';
# 	$gather = '&postusevars';
#     }

#     # Tom: This version thinks that $populate is eval'd instead of the 
#     # bunch of get_eenv() lines, and $gather is eval'd instead
#     # of set_eenv() lines.

#     # However, the compiler can drop in the lines that $populate and
#     # $gather would have.

#     return ($populate,$gather);
# }


