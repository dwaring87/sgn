#!/usr/bin/env perl

#`./run_all_patches.pl -u postgres -p postgres -h localhost -d fixture -e janedoe -s 00085 -t`

use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $dbuser;
my $dbpass;
my $host;
my $db;
my $editinguser;
my $startfrom = 0;
my $test;

GetOptions(
    "user=s" => \$dbuser,
    "pass=s" => \$dbpass,
    "host=s" => \$host,
    "db=s" => \$db,
    "editinguser=s" => \$editinguser,
    "startfrom:i" => \$startfrom,
    "test" => \$test
);

my $db_patch_path = dirname(abs_path($0));
chdir($db_patch_path);

my @folders = grep /[0-9]{5}/, (split "\n", `ls -d */`);

for (my $i = 0; $i < (scalar @folders); $i++) {
    if (($folders[$i]=~s/\/$//r)>=$startfrom){
        chdir($db_patch_path);
        chdir($folders[$i]);
        my @patches = map { s/.pm//r } (split "\n", `ls`);
        for (my $j = 0; $j < (scalar @patches); $j++) {
            my $patch = $patches[$j];
            my $cmd = "echo -ne \"$dbuser\\n$dbpass\" | mx-run $patch -H $host -D $db -u $editinguser".($test?' -t':'');
            print STDERR $cmd."\n";
            system("bash -c '$cmd'");
            print STDERR "\n\n\n";
        }
    }
}
