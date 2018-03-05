#!/usr/bin/perl
# Filename:	flashcache
# Author:	David Ljung Madison <DaveSource.com>
# See License:	http://MarginalHacks.com/License/
# Description:	Copy flash files in your browsers cache
# Dependencies:	Unix command 'lsof'
use strict;

##################################################
# Setup the variables
##################################################
my $PROGNAME = $0; $PROGNAME =~ s|.*/||;

my $LSOF = 'lsof';

my $FIND = 'flash';	# Find flash files
my $POST = 'flv';	# Postfix to save to

# Where we save files
#   %f is $FIND
#   %d is the next available number
#   %p is .$POST
my $DEST = "found%f.%d%p";

##################################################
# Usage
##################################################
sub fatal {
	foreach my $msg (@_) { print STDERR "[$PROGNAME] ERROR:  $msg\n"; }
	exit(-1);
}

sub usage {
	foreach my $msg (@_) { print STDERR "ERROR:  $msg\n"; }
	print STDERR <<USAGE;

Usage:\t$PROGNAME [-d]
  Copies deleted flash files currently open in your browser's cache
  -d             Set debug mode
  -find <str>    What to search for  [default $FIND]
  -post <str>    Postfix for saving files [default $POST]
  -dest <str>    Or just specify full destination [default $DEST]
                 (see the script for meanings of %f, %d, %p)

USAGE
	exit -1;
}

sub parseArgs {
	usage("You need to be on a system that uses /proc") unless -d '/proc';

	my $opt = {
		find => $FIND,
		post => $POST,
		dest => $DEST,
	};
	while (my $arg=shift(@ARGV)) {
		if ($arg =~ /^-h$/) { usage(); }
		if ($arg =~ /^-d$/) { $MAIN::DEBUG=1; next; }
		if ($arg =~ /^-find$/) { $opt->{find} = shift(@ARGV); next; }
		if ($arg =~ /^-post$/) { $opt->{post} = shift(@ARGV); next; }
		if ($arg =~ /^-dest$/) { $opt->{dest} = shift(@ARGV); next; }
		if ($arg =~ /^-/) { usage("Unknown option: $arg"); }
		usage("Too many files specified [$arg and $opt->{file}]") if $opt->{file};
	}

	usage("You need to specify a destination with -dest")
		unless $opt->{dest};
	
	usage("You need to specify something to search for with -find")
		unless $opt->{find};
	
	$opt;
}

sub debug {
	return unless $MAIN::DEBUG;
	foreach my $msg (@_) { print STDERR "[$PROGNAME] $msg\n"; }
}

##################################################
# Main code
##################################################
sub findFiles {
	my ($opt) = @_;
	my @found;
	# 'lsof /'  (The '/' just does files, no sockets, and is faster)
	open(LSOF,"$LSOF /|") || usage("Can't run [$LSOF]");
	while (<LSOF>) {
		next unless /delete/i;
		next unless /\Q$opt->{find}\E/i;
		next if /\.adobe/; 	# Ignore adobe 'flash' db files
		chomp;
		# procname  pid  user   fd
		usage("Found it, can't parse it [$_]")
			unless /^\S+\s+(\d+)\s+\S+\s+(\d+)/;
		push(@found, [$1,$2]);
	}
	usage("Couldn't find any deleted cached $opt->{find} files")
		unless @found;
	@found;
}

sub procPath {
	my ($pid,$fd) = @_;
	my $path = "/proc/$pid";
	usage("Couldn't find $path") unless -d $path;
	$path .= '/fd';
	usage("Couldn't find $path") unless -d $path;
	$path .= "/$fd";
	usage("Couldn't read $path") unless -e $path;
	$path;
}

sub destPath {
	my ($opt) = @_;
	my $p = $opt->{dest};
	$p =~ s/%f/\Q$opt->{find}\E/g;
	$p =~ s/%p/.\Q$opt->{post}\E/g;
	my $num = 0;
	my $path;
	do {
		$path = $p;  $num++;
		$path =~ s/%d/$num/g;
	} until ! -f $path;
	$path;
}

sub main {
	my $opt = parseArgs();
	
	my @found = findFiles($opt);
	foreach my $found ( @found ) {
		my $src = procPath(@$found);
		my $dest = destPath($opt);
		print "$src -> $dest\n";
		system("/bin/cp",$src,$dest);
	}
}
main();
