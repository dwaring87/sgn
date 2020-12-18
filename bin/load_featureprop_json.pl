#! /usr/bin/perl

=head1 NAME

load_featureprop_json.pl - load json feature properties

=head1 DESCRIPTION

usage: load_featureprop_json.pl -H [hostname] -D [database] -U [dbuser] -p [dbpass] -i [infile] -t [type] -n [nd_protocol_id] -c [chunk count]

-H database host name (default: localhost)
-D database name (default: breedbase)
-U database username (default: postgres)
-p database password
-i path to input file (required)
-t cvterm name of featureprop type (cvterm of 'genotype_property' CV) (required)
-n protocol id (nd_protocol_id of the protocol describing the data) (required)
-c chunk count (max number of items to include in a single JSON value)

The input file needs to be formatted as a gff file.  The following columns are used:
- 1: seqid - the name of the feature (chromosome name)
- 4: start - the value’s start position
- 5: end - the value’s end position
- 6: score - the primary score value
- 9: attributes - secondary key/value attributes to be saved with the score

=cut

use strict;
use Getopt::Std;
use CXGN::DB::InsertDBH;
use Bio::Chado::Schema;
use JSON;



# Parse CLI Arguments
our ($opt_H, $opt_D, $opt_U, $opt_p, $opt_i, $opt_t, $opt_n, $opt_c);
getopts('H:D:U:p:i:t:n:c:');

if ( !$opt_i || !$opt_t || !$opt_n ) {
    print STDERR "ERROR: You pust provide the required options: -i infile, -t type, -n protocol\n";
    exit 1;
}

my $dbhost = $opt_H ? $opt_H : "localhost";
my $dbname = $opt_D ? $opt_D : "breedbase";
my $dbuser = $opt_U ? $opt_U : "postgres";
my $dbpass = $opt_p;
my $infile = $opt_i;
my $type_cvterm_name = $opt_t;
my $nd_protocol_id = $opt_n;
my $chunk_size = $opt_c ? $opt_c : 10000;


# Connect to Database
my $dbh = CXGN::DB::Connection->new({ 
    dbhost => $dbhost, 
    dbname => $dbname,
    dbuser => $dbuser,
    dbpass => $dbpass 
});
my $schema = Bio::Chado::Schema->connect(sub { $dbh->get_actual_dbh() });


# Get type cvterm ID
my $cv = $schema->resultset("Cv::Cv")->find({ name => 'genotype_property' });
my $cvterm = $schema->resultset("Cv::Cvterm")->find({
    name  => $type_cvterm_name,
    cv_id => $cv->cv_id()
});
if ( !$cvterm ) {
    print STDERR "ERROR: No matching cvterm found for the specified type [$type_cvterm_name]\n";
    exit 1;
}
my $cvterm_id = $cvterm->cvterm_id();


# TODO: Make sure nd_protocol_id is valid: exists, is appropriate type


# Open the input file
open(my $fh, '<', $infile) or die "Could not open input file\n";

# Properties of the current chunk
my $chunk_feature = undef;  # the name of the chunk's feature (if the current line's feature name is different, start a new chunk)
my $chunk_start = undef;    # the min start position of the chunk's contents
my $chunk_end = undef;      # the max end position of the chunk's contents
my @chunk_values = ();      # the chunk's values (to be converted to JSON array)
my $chunk_count = 0;        # the number of items in the chunk (if the count exceeds the chunk_size, start a new chunk)
my $total = 0;              # the total number of chunks

# Parse the input by line
while ( defined(my $line = <$fh>) ) {
    chomp $line;
    next if ( $line =~ /^#/ );

    # Get data from line
    my @data = split(/\t/, $line);
    my $feature = @data[0];
    my $start = @data[3];
    my $end = @data[4];
    my $score = @data[5] ne "." ? @data[5] : "";
    my $attributes = @data[8];

    # Write the current chunk to the database
    # when the feature changes or the chunk size has been reached
    if ( ($chunk_feature && $feature ne $chunk_feature) || $chunk_count > $chunk_size ) {
        write_chunk();
    }

    # Parse attributes
    my %attribute_hash = ();
    if ( $attributes ne "." ) {
        my @as = split(/;/, $attributes);
        for my $a (@as) {
            my @kv = split(/=/, $a);
            my $key = @kv[0];
            my $value = @kv[1];
            if ( $key eq "score" || $key eq "start" || $key eq "end" ) {
                print STDERR "ERROR: Line has reserved key in attribute list (attributes cannot use keys of 'score', 'start' or 'end')\n";
                print STDERR "LINE: $line\n";
                exit 1;
            }
            $attribute_hash{$key} = $value;
        }
    }

    # Set chunk properties
    if ( !$chunk_feature ) {
        $chunk_feature = $feature;
    }
    if ( !$chunk_start || $start < $chunk_start ) {
        $chunk_start = $start
    }
    if ( !$chunk_end || $end > $chunk_end ) {
        $chunk_end = $end;
    }
    my %value = ( score => $score, start => $start, end => $end );
    %value = (%value, %attribute_hash);

    push @chunk_values, \%value;
    $chunk_count++;
}

# Write the last chunk
write_chunk();

# Commit the changes
$dbh->commit;

print "Wrote $total chunks\n";


sub write_chunk() {

    # Get Feature ID
    my $query = "SELECT feature_id FROM public.feature WHERE uniquename=?" ;
    my $sth = $dbh->prepare($query);
    $sth->execute($chunk_feature);
    my ($feature_id) = $sth->fetchrow_array();

    # TODO: Exit with an error if the feature is not found

    # Convert values to JSON array string
    my $json_str = encode_json(\@chunk_values);

    # Insert into the database
    my $insert = "INSERT INTO public.featureprop_json (feature_id, type_id, nd_protocol_id, start_pos, end_pos, json) VALUES (?, ?, ?, ?, ?, ?);";
    my $ih = $dbh->prepare($insert);
    $ih->execute($feature_id, $cvterm_id, $nd_protocol_id, $chunk_start, $chunk_end, $json_str);

    # Reset chunk properties
    $chunk_feature = undef;
    $chunk_start = undef;
    $chunk_end = undef;
    @chunk_values = ();
    $chunk_count = 0;
    $total++;

    # print STDERR "...Wrote Chunk #$total\n";
    
}