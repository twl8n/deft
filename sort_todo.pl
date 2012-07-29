#!/opt/local/bin/perl
 
$comment = " Todo list (See release_notes.txt for completed tasks)
 Tasks are encoded !,-,+,x,N,C,? as follows:
(!) urgent (-) needs to be worked on (+) current being worked on (x) completed
(N) not necessary, e.g. No, don't work on this (C) comment (?) check or test this
(T) Tom project uses deft not actually relevant to language (H) Same but for Healy";

open IN,"todo.txt";
undef $/;

$cont = <IN>;
close IN;
while ($cont =~ /^([!\-+xNC?TH])(\s.*?)\n{3}/gsm)
{
    push @{$hol{$1}}, "$1$2";
}

open OUT,">todo.txt";
print OUT "$comment\n\n\n";

foreach $key (qw(! ? + - C x T H N))
{
    foreach $out (@{$hol{$key}})
    {
	print OUT "$out\n\n\n";
    }
}
close OUT;
