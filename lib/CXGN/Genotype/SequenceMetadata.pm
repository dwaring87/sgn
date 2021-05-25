package CXGN::Genotype::SequenceMetadata;

=head1 NAME

CXGN::Genotype::SequenceMetadata - used to manage sequence metadata in the featureprop_json table

=head1 USAGE

To preprocess and verify a gff file for the featureprop_json table:
my $smd = CXGN::Genotype::SequenceMetadata->new(bcs_schema => $schema);
my $verification_results = $smd->verify($original_filepath, $processed_filepath, 'Triticum aestivum');


To create a new sequence metadata protocol and store a gff file to the featureprop_json table:
(bcs_schema and type_id are required)
my $smd = CXGN::Genotype::SequenceMetadata->new(bcs_schema => $schema, type_id => $cvterm_id);

1) create a new sequence metadata protocol
(protocol name, protocol description, and reference genome are required)
my %protocol_args = (
    protocol_name => $protocol_name,
    protocol_description => $protocol_description,
    reference_genome => $protocol_reference_genome,
    score_description => $protocol_score_description,
    attributes => \%attributes
);
my $protocol_results = $smd->create_protocol(\%protocol_args);

2) store the preprocessed gff file
my $store_results = $smd->store($processed_filepath, 'Triticum aestivum');


To use an existing sequence metadata protocol and store a gff file to the featureprop_json table:
(bcs_schema, type_id, and nd_protocol_id are required)
my $smd = CXGN::Genotype::SequenceMetadata->new(bcs_schema => $schema, type_id => $cvterm_id, nd_protocol_id => $nd_protocol_id);
my $store_results = $smd->store($processed_filepath, 'Triticum aestivum');


To query the stored sequence metadata:
(bcs_schema and feature_id are required, all other filters are optional)
my $smd = CXGN::Genotype::SequenceMetadata->new(bcs_schema => $schema)
my @attributes = (
    {
        key => 'score',
        nd_protocol_id => 200,
        comparison => 'lt',
        value => 0
    },
    {
        key => 'trait',
        nd_protocol_id => 201,
        comparison => 'eq',
        value => 'grain yield'
    }
);
my $query_results = $smd->query({
    feature_id => $feature_id, 
    start => $start_pos, 
    end => $end_pos,
    reference_genome => $reference_genome,
    type_ids => \@type_ids,
    nd_protocol_ids => \@nd_protocol_ids,
    attributes => \@attributes
});

=head1 DESCRIPTION


=head1 AUTHORS

David Waring <djw64@cornell.edu>

=cut


use strict;
use warnings;
use Moose;
use JSON;

use SGN::Context;
use SGN::Model::Cvterm


has 'shell_script_dir' => (
    isa => 'Str',
    is => 'ro',
    default => '/bin/sequence_metadata'
);

has 'bcs_schema' => (
    isa => 'Bio::Chado::Schema',
    is => 'rw',
    required => 1
);

has 'type_id' => (
    isa => 'Int|Undef',
    is => 'rw'
);

has 'nd_protocol_id' => (
    isa => 'Int|Undef',
    is => 'rw'
);



sub BUILD {
    my $self = shift;
}


#
# Preprocess and verify a gff file for the featureprop_json table
# - Remove comments from the original file
# - Sort the file by seqid and start position
# - Check to make sure all of the seqid's exist as features in the database
#       - the features' organism name must match the provided species argument
# - Check if protocol attributes exist in the file
# - Remove the original file, if processed successfully
#
# Arguments:
# - input: full filepath to the original gff3 file
# - output: full filepath to the processed gff3 file generated by this script
# - species: name of the species to use when checking for existing features (must match feature organism name)
# - protocol_attributes: arrayref of attributes specified by the protocol
#
# Returns a hash with the following keys:
# - processed: 0 if processing fails, 1 if it succeeds
# - verified: 0 if verification fails, 1 if it succeeds
# - missing_features: list of missing features
# - missing_attributes: list of attributes in the protocol that are not in the uploaded file
# - undefined attributes: list attributes in the uploaded file not defined by the protocol
# - error: error message
#
sub verify {
    my $self = shift;
    my $input = shift;
    my $output = shift;
    my $species = shift;
    my $protocol_attributes = shift;
    my $c = SGN::Context->new;

    my %results = (
        processed => 0,
        verified => 0
    );

    # PROCESS THE INPUT FILE
    # Remove comments
    # Sort by seqid and start
    # Save to output file
    my $script = $c->get_conf('basepath') . $self->shell_script_dir . "/preprocess_featureprop_json.sh";
    my $cmd = "bash " . $script . " \"" . $input . "\" \"" . $output . "\"";
    my $rv = system($cmd);
    if ($rv == -1) {
        $results{'error'} = "Could not launch pre-processing script: $!";
    }
    elsif (my $s = $rv & 127) { 
        $results{'error'} = "Pre-processing script died from signal $s";
    }
    elsif (my $e = $rv >> 8)  { 
        $results{'error'} = "Pre-processing script exited with code $e"; 
    }

    # VERIFY THE FEATURES
    # Get a unique list of all seqid's
    # Make sure each seqid matches a feature in the database
    if ( $rv == 0 ) {
        $results{'processed'} = 1;
        
        # Remove original file
        unlink $input;

        # Get unique list of features
        my $script = $c->get_conf('basepath') . $self->shell_script_dir . "/get_unique_features.sh";
        my $cmd = "bash " . $script . " \"" . $output . "\"";
        my @features = `$cmd`;

        # Check each feature in the database
        my @missing = ();
        foreach my $feature ( @features ) {
            chomp($feature);
            my $query = "SELECT feature_id, feature.uniquename, 
                            CONCAT(organism.genus, ' ', REGEXP_REPLACE(organism.species, CONCAT('^', organism.genus, ' '), '')) AS species
                        FROM public.feature 
                        LEFT JOIN public.organism USING (organism_id)
                        WHERE uniquename=? AND species=?;";
            my $sth = $self->bcs_schema->storage->dbh()->prepare($query);
            $sth->execute($feature, $species);
            my ($feature_id) = $sth->fetchrow_array();
            if ( $feature_id eq "" ) {
                push(@missing, $feature . ' (' . $species . ')');
            }
        }
        my $missing_count = scalar(@missing);
        $results{'missing_features'} = \@missing;

        # Verified successfully if no missing features
        if ( $missing_count == 0 ) {
            $results{'verified'} = 1;
        }


        # VERIFY THE ATTRIBUTES
        # Get file attributes
        my @missing_attributes = ();
        my @undefined_attributes = ();
        my $attributes_script = $c->get_conf('basepath') . $self->shell_script_dir . "/get_unique_attributes.sh";
        my $attributes_cmd = "bash " . $attributes_script . " \"" . $output . "\"";
        my @file_attributes = `$attributes_cmd`;
        chomp(@file_attributes);

        # Compare file and protocol attributes
        my $has_undefined_attributes = 0;
        foreach my $file_attribute ( @file_attributes ) {
            if ( !grep( /^$file_attribute$/, @$protocol_attributes ) ) {
                push(@undefined_attributes, $file_attribute);
                $has_undefined_attributes = 1;
            }
        }
        my $has_missing_attributes = 0;
        foreach my $protocol_attribute ( @$protocol_attributes ) {
            if ( !grep( /^$protocol_attribute$/, @file_attributes) ) {
                push(@missing_attributes, $protocol_attribute);
                $has_missing_attributes = 1;
            }
        }

        # Set attribute response(s)
        if ( $has_undefined_attributes ) {
            $results{'undefined_attributes'} = \@undefined_attributes;
        }
        if ( $has_missing_attributes ) {
            $results{'missing_attributes'} = \@missing_attributes;
        }
    }

    return(\%results);
}


#
# Create a new Sequence Metadata Protocol with the specified properties
#
# Arguments: as a hash with the following keys:
# - protocol_name = the name of the sequence metadata protocol
# - protocol_description = the description of the sequence metadata protocol
# - reference_genome = the name of the reference genome used by the sequence metadata positions
# - score_description = (optional) the description of the store value
# - attributes = (optional) a hashref of attributes (keys) and their descriptions (values)
# - links = (optional) a hashref of external links (keys = title, values = URL template)
# 
# Returns a hash with the following keys:
# - error: error message
# - created: 0 if creation failed, 1 if it succeeds
# - nd_protocol_id: the id of the new protocol
#
sub create_protocol {
    my $self = shift;
    my $args = shift;
    my $protocol_name = $args->{'protocol_name'};
    my $protocol_description = $args->{'protocol_description'};
    my $reference_genome = $args->{'reference_genome'};
    my $score_description = $args->{'score_description'};
    my $attributes = $args->{'attributes'};
    my $links = $args->{'links'};

    # Protocol Results
    my %results = (
        created => 0,
        nd_protocol_id => 0
    );

    # Make sure SMD type_id is set
    if ( !defined $self->type_id || $self->type_id eq '' ) {
        $results{'error'} = "Sequence Metadata type_id not set!";
        return(\%results);
    }

    # Check required arguments
    if ( !$protocol_name || $protocol_name eq '' ) {
        $results{'error'} = "Protocol name not set!";
        return(\%results);
    }
    if ( !$protocol_description || $protocol_description eq '' ) {
        $results{'error'} = "Protocol description not set!";
        return(\%results);
    }
    if ( !$reference_genome || $reference_genome eq '' ) {
        $results{'error'} = "Reference genome not set!";
        return(\%results);
    }

    # Get type name from type_id
    my $sequence_metadata_type = $self->bcs_schema->resultset("Cv::Cvterm")->find({ cvterm_id=>$self->type_id })->name();
    
    # Set the protocol props
    my %sequence_metadata_protocol_props = (
        sequence_metadata_type_id => $self->type_id,
        sequence_metadata_type => $sequence_metadata_type,
        reference_genome => $reference_genome
    );
    if ( defined $score_description && $score_description ne '' ) {
        $sequence_metadata_protocol_props{'score_description'} = $score_description;
    }
    if ( defined $attributes ) {
        $sequence_metadata_protocol_props{'attribute_descriptions'} = $attributes;
    }
    if ( defined $links ) {
        $sequence_metadata_protocol_props{'links'} = $links;
    }
    
    # Create Protocol with props
    my $sequence_metadata_protocol_type_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'sequence_metadata_protocol', 'protocol_type')->cvterm_id();
    my $sequence_metadata_protocol_prop_cvterm_id = SGN::Model::Cvterm->get_cvterm_row($self->bcs_schema, 'sequence_metadata_protocol_properties', 'protocol_property')->cvterm_id();
    my $protocol = $self->bcs_schema->resultset('NaturalDiversity::NdProtocol')->create({
        name => $protocol_name,
        type_id => $sequence_metadata_protocol_type_id,
        nd_protocolprops => [{type_id => $sequence_metadata_protocol_prop_cvterm_id, value => encode_json \%sequence_metadata_protocol_props}]
    });
    my $protocol_id = $protocol->nd_protocol_id();
    
    # Update protocol description
    my $dbh = $self->bcs_schema->storage->dbh();
    my $sql = "UPDATE nd_protocol SET description=? WHERE nd_protocol_id=?;";
    my $sth = $dbh->prepare($sql);
    $sth->execute($protocol_description, $protocol_id);

    # Set the protocol id
    $self->nd_protocol_id($protocol_id);

    # Return Results
    $results{'created'} = 1;
    $results{'nd_protocol_id'} = $protocol_id;
    return(\%results);

}


#
# Store sequence metadata from a gff file to the featureprop_json table
#
# Arguments:
# - input: the full filepath to the gff3 file to parse
# - species: the name of the species to be used when finding matching features from the input file
# - chunk_size: (optional) max number of items to store in a single database row (default 8000)
#
# Returns a hash with the following keys:
# - error: error message
# - stored: 0 if storing failed, 1 if it succeeds
# - chunks: the number of chunks stored
#
sub store {
    my $self = shift;
    my $input = shift;
    my $species = shift;
    my $chunk_size = shift;

    my %results = (
        stored => 0,
        chunks => 0
    );

    # Make sure type_id and nd_protocol_id are set
    if ( !defined $self->type_id || $self->type_id eq '' ) {
       $results{'error'} = "Sequence Metadata type_id not set!";
       return(\%results);
    }
    if ( !defined $self->nd_protocol_id || $self->nd_protocol_id eq '' ) {
        $results{'error'} = "Sequence Metadata nd_protocol_id not set!";
        return(\%results);
    }

    # Set default chunk size
    if ( !defined $chunk_size || $chunk_size eq '' ) {
        $chunk_size = 8000;
    }

    # Check cvterm id
    my $cvterm = $self->bcs_schema->resultset("Cv::Cvterm")->find({ cvterm_id => $self->type_id });
    if ( !$cvterm ) {
        $results{'error'} = "No matching cvterm found for the specified type id";
        return(\%results);
    }

    # Check nd protocol id
    my $nd_protocol = $self->bcs_schema->resultset("NaturalDiversity::NdProtocol")->find({ nd_protocol_id => $self->nd_protocol_id });
    if ( !$nd_protocol ) {
        $results{'error'} = "No matching nd protocol found for the specified nd protocol id";
        return(\%results);
    }



    # Open the input file
    open(my $fh, '<', $input) or die "Could not open input file\n";

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
        my $feature = $data[0] ne "." ? $data[0] : "";
        my $start = $data[3] ne "." ? $data[3] : "";
        my $end = $data[4] ne "." ? $data[4] : "";
        my $score = $data[5] ne "." ? $data[5] : "";
        my $attributes = $data[8] ne "." ? $data[8] : "";

        # Put unknown start / stop positions at 0
        $start = $start eq "" ? 0 : $start;
        $end = $end eq "" ? 0 : $end;

        # Write the current chunk to the database
        # when the feature changes or the chunk size has been reached
        if ( ($chunk_feature && $feature ne $chunk_feature) || $chunk_count > $chunk_size ) {
            _write_chunk($self, $chunk_feature, $species, \@chunk_values, $chunk_start, $chunk_end);

            # Reset chunk properties
            $chunk_feature = undef;
            $chunk_start = undef;
            $chunk_end = undef;
            @chunk_values = ();
            $chunk_count = 0;
            $total++;
        }

        # Parse attributes
        my %attribute_hash = ();
        if ( $attributes ne "." ) {
            my @as = split(/;/, $attributes);
            for my $a (@as) {
                my @kv = split(/=/, $a);
                my $key = $kv[0];
                my $value = $kv[1];
                ($value) = $value =~ /^"?([^"]*)"?$/;
                if ( $key eq "score" || $key eq "start" || $key eq "end" ) {
                    $results{'error'} = "Line has reserved key in attribute list (attributes cannot use keys of 'score', 'start' or 'end')";
                    return(\%results);
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
    _write_chunk($self, $chunk_feature, $species, \@chunk_values, $chunk_start, $chunk_end);
    $total++;

    # Return the number of chunks written
    $results{'stored'} = 1;
    $results{'chunks'} = $total;
    return(\%results);
}


#
# Write a chunk / row of sequence metadata to the database
#
sub _write_chunk() {
    my $self = shift;
    my $chunk_feature = shift;
    my $species = shift;
    my $chunk_values = shift;
    my $chunk_start = shift;
    my $chunk_end = shift;

    my $dbh = $self->bcs_schema->storage->dbh();
    my $type_id = $self->type_id;
    my $nd_protocol_id = $self->nd_protocol_id;

    # Get Feature ID
    my $query = "SELECT feature_id, feature.uniquename, 
                    CONCAT(organism.genus, ' ', REGEXP_REPLACE(organism.species, CONCAT('^', organism.genus, ' '), '')) AS species
                FROM public.feature 
                LEFT JOIN public.organism USING (organism_id)
                WHERE uniquename=? AND species=?;";
    my $sth = $dbh->prepare($query);
    $sth->execute($chunk_feature, $species);
    my ($feature_id) = $sth->fetchrow_array();

    # Check Feature ID
    if ( !$feature_id || $feature_id eq "" ) {
        die "No matching feature for specified seqid [$chunk_feature ($species)]\n";
    }

    # Convert values to JSON array string
    my $json_str = encode_json($chunk_values);

    # Insert into the database
    my $insert = "INSERT INTO public.featureprop_json (feature_id, type_id, nd_protocol_id, start_pos, end_pos, json) VALUES (?, ?, ?, ?, ?, ?);";
    my $ih = $dbh->prepare($insert);
    $ih->execute($feature_id, $type_id, $nd_protocol_id, $chunk_start, $chunk_end, $json_str);
}


#
# Query the sequence metadata stored in the featureprop_json table with the provided filter parameters
#
# Arguments (as a hash with the following keys):
# - feature_id = id of feature associated with the sequence metadata
# - start = (optional) start position of query region (default: 0)
# - end = (optional) end position of query region (default: feature max)
# - reference_genome = (required if start and/or end provided) the reference genome name of the start and/or end positions
# - type_ids = (optional) array of sequence metadata cvterm ids (default: object type_id, if defined, or include all)
# - nd_protocol_ids = (optional) array of nd_protocol_ids (default: object nd_protocol_id, if defined, or include all)
# - attributes = (optional) an array of attribute properties to include in the filter (default: none)
#       the attribute properties are a hash with the following keys:
#           - key = attribute key (score, secondary attribute key, etc)
#           - nd_protocol_id = the id of the protocol to apply this attribute filter to
#           - comparison = one of: con, eq, lt, lte, gt, gte to use as the comparison of the stored value to the specified value
#           - value = the value to use in the comparison
#
# Returns a hash with the following keys:
#   - error: an error message, if an error was encountered
#   - results: an array of sequence metadata objects with the following keys:
#       - featureprop_json_id = id of associated featureprop_json chunk
#       - feature_id = id of associated feature
#       - feature_name = name of associated feature
#       - type_id = cvterm_id of sequence metadata type
#       - type_name = name of sequence metadata type
#       - nd_protocol_id = id of associated nd_protocol
#       - nd_protocol_name = name of associated nd_protocol
#       - start = start position of sequence metadata
#       - end = end position of sequence metadata
#       - score = primary score value of sequence metadata
#       - attributes = hash of secondary key/value attributes
#       - links = hash of external link titles and URLs
#
sub query {
    my ($self, $args) = @_;
    my $feature_id = $args->{feature_id};
    my $start = $args->{start};
    my $end = $args->{end};
    my $reference_genome = $args->{reference_genome};
    my $min_score = $args->{min_score};
    my $max_score = $args->{max_score};
    my $type_ids = $args->{type_ids};
    my $nd_protocol_ids = $args->{nd_protocol_ids};
    my $attributes = $args->{attributes};
    my $MAX_CHUNK_COUNT = 1000;  # The max number of chunks to try to query at once, more than this returns an error

    my $schema = $self->bcs_schema;
    my $dbh = $schema->storage->dbh();

    my %results = (
        results => ()
    );

    # Check for required parameters
    if ( !defined $feature_id || $feature_id eq '' ) {
        $results{'error'} = "Feature ID not provided!";
        return(\%results);
    }
    if ( (!defined $reference_genome || $reference_genome eq '') && (defined $start || defined $end) ) {
        $results{'error'} = "Reference genome must be provided with start and/or end positions(s)!";
        return(\%results);
    }

    # Set undefined start / end positions
    if ( !defined $start || $start eq '' ) {
        $start = 0;
    }
    if ( !defined $end || $end eq '' ) {
        my $q = "SELECT MAX(end_pos) FROM public.featureprop_json WHERE feature_id = ?";
        my $h = $dbh->prepare($q);
        $h->execute($feature_id);
        ($end) = $h->fetchrow_array();
    }

    # Set undefined type_ids / nd_protocol_ids (use class arguments, if available)
    if ( !defined $type_ids ) {
        $type_ids = $self->type_id ? [$self->type_id] : [];
    }
    if ( !defined $nd_protocol_ids ) {
        $nd_protocol_ids = $self->nd_protocol_id ? [$self->nd_protocol_id] : [];
    }

    # Check if feature_id exists
    my $feature_rs = $schema->resultset("Sequence::Feature")->find({ feature_id => $feature_id });
    if ( !defined $feature_rs ) {
        $results{'error'} = 'Could not find matching feature!';
        return(\%results);
    }

    # Check if type_id exists and is valid type
    foreach my $type_id (@$type_ids) {
        my $cv_rs = $schema->resultset('Cv::Cv')->find({ name => "sequence_metadata_types" });
        my $cvterm_rs = $schema->resultset('Cv::Cvterm')->find({ cvterm_id => $type_id, cv_id => $cv_rs->cv_id() });
        if ( !defined $cvterm_rs ) {
            $results{'error'} = "Could not find matching sequence metadata type [$type_id]!";
            return(\%results);
        }
    }

    # Check if nd_protocol_id exists and is valid type
    foreach my $nd_protocol_id (@$nd_protocol_ids) {
        
        # Check for existing sequence metadata protocol
        my $protocol_cv_rs = $schema->resultset('Cv::Cv')->find({ name => "protocol_type" });
        my $protocol_cvterm_rs = $schema->resultset('Cv::Cvterm')->find({ name => "sequence_metadata_protocol", cv_id => $protocol_cv_rs->cv_id() });
        my $protocol_rs = $schema->resultset("NaturalDiversity::NdProtocol")->find({ nd_protocol_id => $nd_protocol_id, type_id => $protocol_cvterm_rs->cvterm_id() });
        if ( !defined $protocol_rs ) {
            $results{'error'} = "Could not find matching nd_protocol [$nd_protocol_id]!";
            return(\%results);
        }

    }

    # Get protocol external link definitions
    my %external_links = ();
    my $link_query = "SELECT nd_protocol_id, value->>'links' AS links
                FROM nd_protocolprop
                WHERE type_id = (SELECT cvterm_id FROM public.cvterm WHERE name = 'sequence_metadata_protocol_properties');";
    my $lh = $dbh->prepare($link_query);
    $lh->execute();
    while (my ($nd_protocol_id, $link_json) = $lh->fetchrow_array()) {
        my $links = defined $link_json ? decode_json $link_json : decode_json '{}';
        $external_links{$nd_protocol_id} = $links;
    }

    # Build the base query conditions
    my @query_params = ($feature_id, $start, $start, $end, $end, $start, $end);
    my $query_where = " WHERE featureprop_json.feature_id = ? ";
    $query_where .= " AND ((featureprop_json.start_pos <= ? AND featureprop_json.end_pos >= ?) OR (featureprop_json.start_pos <= ? AND featureprop_json.end_pos >= ?) OR (featureprop_json.start_pos >= ? AND featureprop_json.end_pos <= ?)) ";
    if ( $type_ids && @$type_ids ) {
        $query_where .= " AND featureprop_json.type_id IN (@{[join',', ('?') x @$type_ids]})";
        push(@query_params, @$type_ids);
    }
    if ( $nd_protocol_ids && @$nd_protocol_ids ) {
        $query_where .= " AND featureprop_json.nd_protocol_id IN (@{[join',', ('?') x @$nd_protocol_ids]})";
        push(@query_params, @$nd_protocol_ids);
    }
    if ( defined $reference_genome && $reference_genome ne '' ) {
        $query_where .= " AND featureprop_json.nd_protocol_id IN (SELECT nd_protocol_id FROM nd_protocolprop WHERE type_id = (SELECT cvterm_id FROM public.cvterm WHERE name='sequence_metadata_protocol_properties') AND value->>'reference_genome' = ?) ";
        push(@query_params, $reference_genome);
    }

    # Estimate result size by getting number of matching chunks
    my $size_query = "SELECT COUNT(featureprop_json_id) ";
    $size_query .= "FROM public.featureprop_json";
    $size_query .= $query_where;
    my $sh = $dbh->prepare($size_query);
    $sh->execute(@query_params);
    my ($chunk_count) = $sh->fetchrow_array();
    
    # DATA QUERY TOO LARGE: return with an error message
    if ( $chunk_count > $MAX_CHUNK_COUNT ) {
        $results{'error'} = "The requested query is too large to perform at once.  Try filtering the data by including fewer data types/protocols and/or a smaller sequence range.";
        return(\%results);
    }


    # Build query
    my $query = "SELECT featureprop_json.featureprop_json_id, featureprop_json.feature_id, feature.name AS feature_name, (s->>'start')::int AS start, (s->>'end')::int AS end, featureprop_json.type_id, cvterm.name AS type_name, featureprop_json.nd_protocol_id, nd_protocol.name AS nd_protocol_name, s AS attributes
FROM featureprop_json
LEFT JOIN jsonb_array_elements(featureprop_json.json) as s(data) on true
LEFT JOIN public.feature ON feature.feature_id = featureprop_json.feature_id
LEFT JOIN public.cvterm ON cvterm.cvterm_id = featureprop_json.type_id
LEFT JOIN public.nd_protocol ON nd_protocol.nd_protocol_id = featureprop_json.nd_protocol_id";

    # Add aditional conditions
    $query .= $query_where;
    $query .= " AND (
((s->>'start')::int >= ? AND (s->>'end')::int <= ?) 
OR ((s->>'start')::int >= ? AND (s->>'start')::int <= ? AND (s->>'end')::int > ?) 
OR ((s->>'start')::int < ? AND (s->>'end')::int >= ? AND (s->>'end')::int <= ?) 
OR ((s->>'start')::int < ? AND (s->>'end')::int > ?)
)";
    push(@query_params, $start, $end, $start, $end, $end, $start, $start, $end, $start, $end);
    if ( $attributes && @$attributes ) {
        $query .= " AND (";
        my @aq = ();
        foreach my $a (@$attributes ) {
            my $ap = $a->{nd_protocol_id};
            my $ak = $a->{key};
            my $ac = $a->{comparison};
            my $av = $a->{value};
            
            my $cast = undef;
            my $comp = undef;
            if ( $ac eq "lt" ) {
                $comp = "<";
                $cast = "real";
            }
            elsif ( $ac eq "lte" ) {
                $comp = "<=";
                $cast = "real";
            }
            elsif ( $ac eq "gt" ) {
                $comp = ">";
                $cast = "real";
            }
            elsif ( $ac eq "gte" ) {
                $comp = ">=";
                $cast = "real";
            }
            elsif ( $ac eq "con" ) {
                $comp = "LIKE";
                $cast = "text";
                $av = "%" . $av . "%";
            }
            else {
                $comp = "=";
                $cast = "text";
            }

            my $q = "(featureprop_json.nd_protocol_id <> ? OR (featureprop_json.nd_protocol_id = ?";
            $q .= " AND CASE WHEN s->>? = '' THEN FALSE ELSE (s->>?)::$cast $comp ? END))";

            push(@aq, $q);
            push(@query_params, $ap, $ap, $ak, $ak, $av);
        }
        $query .= join(" AND ", @aq);
        $query .= ") ";
    }
    $query .= " ORDER BY start ASC";

    # print STDERR "QUERY:\n";
    # print STDERR "$query\n";
    # print STDERR "QUERY PARAMS:\n";
    # use Data::Dumper;
    # print STDERR Dumper \@query_params;

    # Perform the search
    my $h = $dbh->prepare($query);
    $h->execute(@query_params);

    # Parse the results
    my @matches = ();
    while (my ($featureprop_json_id, $feature_id, $feature_name, $start, $end, $type_id, $type_name, $nd_protocol_id, $nd_protocol_name, $attributes_json) = $h->fetchrow_array()) {
        my $attributes = decode_json $attributes_json;
        my $score = $attributes->{score};
        delete $attributes->{score};
        delete $attributes->{start};
        delete $attributes->{end};

        # Build Links, if provided and variables are defined
        my %links = ();
        my $defs = $external_links{$nd_protocol_id};
        if ( defined $defs ) {
            foreach my $title (keys %$defs) {
                my $template = $defs->{$title};
                my @variables = $template =~ /\{\{([^\}]*)\}\}/g;

                # Get values for replacement
                my $skip = 0;       # flag to skip link if one or more variables are undefined for this match
                my %values = ();    # hash of variables and values to replace in the link
                foreach my $variable (@variables) {
                    if ( $variable eq 'feature' ) {
                        $values{'feature'} = $feature_name;
                    }
                    elsif ( $variable eq 'start' ) {
                        $values{'start'} = $start;
                    }
                    elsif ( $variable eq 'end' ) {
                        $values{'end'} = $end;
                    }
                    else {
                        my $value = $attributes->{$variable};
                        if ( defined $value && $value ne '' ) {
                            $values{$variable} = $value;
                        }
                        else {
                            $skip = 1;
                        }
                    }
                }

                # Build link, replace variables with values
                if ( !$skip ) {
                    my $link = $template;
                    foreach my $k (keys %values) {
                        my $v = $values{$k};
                        my $f = "\\{\\{$k\\}\\}";
                        $link =~ s/$f/$v/g;
                    }
                    $links{$title} = $link;
                }
            }
        }

        my %match = (
            featureprop_json_id => $featureprop_json_id,
            feature_id => $feature_id,
            feature_name => $feature_name,
            type_id => $type_id,
            type_name => $type_name,
            nd_protocol_id => $nd_protocol_id,
            nd_protocol_name => $nd_protocol_name,
            score => $score ne '' ? $score += 0 : '',
            start => $start += 0,
            end => $end += 0,
            attributes => $attributes,
            links => \%links
        );
        push(@matches, \%match);
    }

    # Return the results
    $results{'results'} = \@matches;
    return(\%results);
}


1;