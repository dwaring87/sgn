
=head1 NAME 

oldresearchupdates.pl - a module to display content from /homepage/oldresearchupdates.mas mason that reads from a file.

=head1 DESCRIPTION

The module does not require any parameters. 

=head1 AUTHOR

Surya Saha <ss2489 at cornell dot edu>

=cut

use strict;

use CXGN::MasonFactory;

my $m = CXGN::MasonFactory->new();

$m->exec('/homepage/oldresearchupdates.mas');
