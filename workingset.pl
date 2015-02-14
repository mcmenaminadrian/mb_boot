#!/usr/bin/perl
use strict;
use warnings;

my @fields;
my %workingset = ();
my $count = 0;
my @last;

my $file =  $ARGV[0] or die "Please specify CSV file on command line\n";
my $instcount = $ARGV[1] or die "Please specify instruction count\n";
my $pageshift = $ARGV[2] or die "Please specify page shift (eg 12 for 4k pages)\n";

open(my $data, '<', $file) or die "Could not open $file\n";
print "Count, WSS\n";

while (my $line = <$data>) {
	$count = $count + 1;
	chomp $line;
	@fields = split ",", $line;
	my $page = oct($fields[2]) >> $pageshift;
	if ($count > $instcount) {
		my $oldvalue = $last[$count%($instcount + 1)];
		my $valuecount = $workingset{$oldvalue};
		if ($valuecount eq 1) { delete $workingset{$oldvalue};}
		else {$workingset{$oldvalue} = $valuecount - 1;}
	}
	if (exists $workingset{$page}) {$workingset{$page} = $workingset{$page} + 1}
	else {$workingset{$page} = 1;}
	$last[$count % ($instcount + 1)] = $page;
	print "$count,", scalar (keys(%workingset)), "\n";
}
