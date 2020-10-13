

package SGN::Controller::AJAX::Analyze::TrialSummary;

use Moose;

use strict;
use warnings;
use Data::Dumper;
use SGN::Controller::AJAX::List;
use CXGN::List::Transform;
use CXGN::Phenotypes::SearchFactory;
use CXGN::BreederSearch;

BEGIN { extends 'Catalyst::Controller::REST'; };

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
    );


#
# AJAX CONTROLLER: /ajax/analyze/traits_by_trials_list
#
# Get the traits that are observed in the specified list of trials
#
# Query Params:
#   trials_list_id = List ID for a list of trials
#   all = set to 1 to only include traits observed in ALL of the trials
#         optional - default is to include traits observed in ANY of the trials
#
# Returns:
#   A JSON response with the list of traits (IDs and names) in the specified trials
#
sub get_traits_by_trial_list : Path('/ajax/analyze/traits_by_trials_list') Args(0) {
  my $self = shift;
  my $c = shift;

  # Get Query Params
  my $trials_list_id = $c->req->param("trials_list_id");
  my $all = $c->req->param("all") eq "1" ? 1 : 0;

  # Get Trial IDs from the Trial List ID
  my $trial_ids = trial_list_id_to_trial_ids($c, $trials_list_id);

  # Get the Traits from the Trials
  my $dbh = $c->dbc->dbh();
  my $bs = CXGN::BreederSearch->new({ dbh=>$dbh });
  my $criteria_list = ['trials', 'traits'];
  my $dataref = {
    'traits' => {
      'trials' => join(",", @{$trial_ids})
    }
  };
  my $queryref = {
    'traits' => {
      'trials' => $all
    }
  };
  my $results_ref = $bs->metadata_query($criteria_list, $dataref, $queryref);
  my $traits = $results_ref->{results};

  # Parse Traits into return hash
  my @rtn = ();
  foreach my $trait (@$traits) {
    my $t = {
      'id' => $trait->[0],
      'name' => $trait->[1]
    };
    push(@rtn, $t);
  }

  # Return the Results
  $c->stash->{rest} = \@rtn;
  return;
}

#
# AJAX CONTROLLER: /ajax/analyze/trial_trait_summary
# 
# Summarize trial for a specified list of Trials and Traits.
#
# Query Params:
#   trials_list_id = List ID for a list of trials
#   trait_id = each of the Trait IDs to include in the summary
#
# Returns:
#   A JSON response with overall lsmeans and trait summaries
#
sub summarize_trials_by_traits : Path('/ajax/analyze/trial_trait_summary') Args(0) {
  my $self = shift;
  my $c = shift;
  my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
  
  # Get Query Params
  my $trials_list_id = $c->req->param("trials_list_id");
  my @trait_ids = $c->req->param("trait_id");
  
  # Get Trial IDs from List
  my $trial_ids = trial_list_id_to_trial_ids($c, $trials_list_id);

  # Get phenotype plot data for the matching Trials and Traits
  my $phenotypes_search = CXGN::Phenotypes::SearchFactory->instantiate(
    'MaterializedViewTable',
    {
      bcs_schema=>$schema,
      data_level=>"plot",
      trait_list=>\@trait_ids,
      trial_list=>$trial_ids
    }
  );
  my @data = $phenotypes_search->search();
  my $results = $data[0];

  # Get Trait Display Names
  my %trait_info;
  foreach my $trait_id (@trait_ids) {
    my $cvterm = $schema->resultset('Cv::Cvterm')->find({
      'me.cvterm_id' => $trait_id
    });
    $trait_info{$trait_id} = $cvterm->name;
  }

  # Parse the phenotype results into a 2D array of rows
  my $rows = plot_data_to_rows($results, \%trait_info);

  # Write the rows to a CSV tempfile
  my ($src_file, $out_dir) = $self->write_rows_to_tempfile($c, $rows);

  # Run the R script
  system("R CMD BATCH --no-save --no-restore '--args src=\"$src_file\" out=\"$out_dir\"' \"" . $c->config->{basepath} . "/R/summarize_trials_lsm.R\" \"$out_dir/output.txt\"");

  # Read overall lsmeans results
  my %overall_results;
  $overall_results{'lsmeans'} = $self->csv_to_JSON($out_dir . "/lsmeans.csv");
  $overall_results{'lsmeans_metadata'} = $self->csv_to_JSON($out_dir . "/lsmeans.metadata.csv");

  # Read individual trait results
  my %trait_results;
  foreach my $trait (@{$overall_results{'lsmeans_metadata'}}) {
    my $trait_code = $trait->{'trait_code'};
    my %t;
    $t{'results'} = $self->csv_to_JSON($out_dir . "/" . $trait_code . ".csv");
    $t{'metadata'} = $self->csv_to_JSON($out_dir . "/" . $trait_code . ".metadata.csv");
    $trait_results{$trait_code} = \%t;
  }

  # Return the Results
  $c->stash->{rest} = {
    overall => \%overall_results,
    traits => \%trait_results
  };

  return;
}


# 
# Parse the phenotype plot data into a 2D array 
# The first Array is the header names (trait, trial, accession, value)
# Each following Array is the data from a single plot observation
#
# Params:
#   $results = results from phenotype search
#   $trait_info = hashref to hash of trait ids to trait names
#
# Returns: a 2D array of plot data from the phenotype search
#
sub plot_data_to_rows {
  my $results = shift;
  my $trait_info = shift;

  # Set up csv data with headers
  my @rows = ();
  my @h = ("trait", "trial", "accession", "value");
  push(@rows, \@h);

  # Parse each plot data item into rows
  foreach my $plot (@$results) {
    my $trial = $plot->{trial_name};
    my $accession = $plot->{germplasm_uniquename};
    my $observations = $plot->{observations};

    # Add each trait value to the row
    foreach my $trait_id (keys %{$trait_info}) {

      # Parse each observation into an array of row values
      my $f = 0;
      foreach my $observation (@$observations) {
        my @r = ();
        if ( $observation->{trait_id} == $trait_id ) {
          push(@r, $trait_info->{$trait_id});
          push(@r, $trial);
          push(@r, $accession);
          push(@r, $observation->{value});
          push(@rows, \@r);
          $f = 1;
        }
      }
      if ( $f == 0 ) {
        my @r = ();
        push(@r, $trait_info->{$trait_id});
        push(@r, $trial);
        push(@r, $accession);
        push(@r, "");
        push(@rows, \@r);
      }

    }
  }

  # Return the array of rows
  return \@rows;
}



#
# Write a 2D Array to a tempfile as a CSV file (comma separated, quote escaped)
# - the first index in the array is the line in the CSV file
# - the second index in the array is the cell contents for that line
#
# Params:
#   $c = Catalyst context
#   $rows = Arrayref to 2D array of rows and cell contents
#
# Returns: (
#   full path to tempfile,
#   full path to output directory
# )
#
sub write_rows_to_tempfile {
  my $self = shift;
  my $c = shift;
  my $rows = shift;

  # Get Tempfile to write CSV to
  my $dir = $c->tempfiles_subdir('data_export');
  my ($fh, $tempfile) = $c->tempfile(TEMPLATE=>"data_export/trial_summary_XXXXX");
  my $file_path = $c->config->{basepath}."/".$tempfile;
  
  # Set output directory
  my $out_dir = $c->config->{basepath} . "/" . $tempfile . "_results";
  mkdir $out_dir, 0777;
  
  # Print each row to the tempfile
  foreach my $r (@$rows) {
    print $fh "\"" . join("\",\"", @$r) . "\"";
    print $fh "\n";
  }

  close($fh);
  return ($file_path, $out_dir);
}


#
# Read a CSV file and convert the contents to JSON
# Note: this assumes the file has a header row
#
# Params:
#   path = file path to CSV file
#
# Returns:
#   an Array of hashes where each hash is a row 
#   and the hash keys are the header names and the 
#   hash values are the cell contents
#
sub csv_to_JSON {
  my $self = shift;
  my $path = shift;

  my @headers = ();
  my @rows = ();
  open(my $in, "<:encoding(utf8)", $path) or die "$path: $!";
  while ( my $line = <$in> ) {
    chomp $line;
    my @f = split(",", $line);
    my @fields = ();
    foreach my $i (@f) {
      $i =~ s/^"(.*)"$/$1/;
      push(@fields, $i);
    }

    if ( !@headers ) {
      @headers = @fields;
    }
    else {
      my %r;
      for my $i ( 0 .. $#headers ) {
        my $h = $headers[$i];
        my $v = $fields[$i];
        $r{$h} = $v;
      }
      push(@rows, \%r);
    }
  }

  return(\@rows);
}

#
# Get the Trial IDs of the Trials in the specified List
#
# Params:
#   c = Catalyst reference
#   trials_list_id = List ID of Trials List
#
# Returns:
#   an Array of Trial IDs of Trials in the specified List
#
sub trial_list_id_to_trial_ids {
  my $c = shift;
  my $trials_list_id = shift;
  my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");

  # Get List Info
  my $trial_data;
  if ($trials_list_id) {
    $trial_data = SGN::Controller::AJAX::List->retrieve_list($c, $trials_list_id);
  }

  # Get Trial IDs
  my @trial_list = map { $_->[1] } @$trial_data;
  my $t = CXGN::List::Transform->new();
  my $trial_t = $t->can_transform("trials", "trial_ids");
  my $trial_id_hash = $t->transform($schema, $trial_t, \@trial_list);
  my @trial_ids = @{$trial_id_hash->{transform}};

  return(\@trial_ids);
}

1;