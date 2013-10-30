#!/usr/bin/env perl

@node_list = ("node01", "node02", "node03", "node04", "node05", "node06", "node07", "node08",  "node09", "node10");

my $who = `whoami`;
chomp($who);
if ($who ne "root") {
    print "Must be run as root\n";
    exit(1);
}

foreach my $node (@node_list) {
	print "\n### reboot $node ...\n";
	my @cmd = qw/cmsh -x -c/;
	push(@cmd, "device; use $node; reboot; commit");
	my $ret = system(@cmd);
	abort("cmsh failed to set category $category for $node: $?\n") if ($ret != 0);
	print "\n";
}

