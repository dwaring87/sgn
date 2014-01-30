package CXGN::Pedigree::AddCrosses;

=head1 NAME

CXGN::Pedigree::AddCrosses - a module to add cross experiments.

=head1 USAGE

 my $cross_add = CXGN::Pedigree::AddCrosses->new({ schema => $schema, location => $location_name, program => $program_name, crosses =>  \@array_of_pedigree_objects} );
 my $validated = $cross_add->validate_crosses(); #is true when all of the crosses are valid and the accessions they point to exist in the database.
 $cross_add->add_crosses();

=head1 DESCRIPTION

Adds an array of crosses. The stock names used in the cross must already exist in the database, and the verify function does this check.   This module is intended to be used in independent loading scripts and interactive dialogs.

=head1 AUTHORS

 Jeremy D. Edwards (jde22@cornell.edu)

=cut

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Try::Tiny;
use Bio::GeneticRelationships::Pedigree;
use Bio::GeneticRelationships::Individual;
use CXGN::Stock::StockLookup;
use CXGN::Location::LocationLookup;
#use CXGN::Trial::TrialLookup;
use CXGN::BreedersToolbox::Projects;

class_type 'Pedigree', { class => 'Bio::GeneticRelationships::Pedigree' };
has 'schema' => (
		 is       => 'rw',
		 isa      => 'DBIx::Class::Schema',
		 predicate => 'has_schema',
		 required => 1,
		);
has 'crosses' => (isa =>'ArrayRef[Pedigree]', is => 'rw', predicate => 'has_crosses', required => 1,);
has 'location' => (isa =>'Str', is => 'rw', predicate => 'has_location', required => 1,);
has 'program' => (isa =>'Str', is => 'rw', predicate => 'has_program', required => 1,);

sub add_crosses {
  my $self = shift;
  my $schema = $self->get_schema();
  my @crosses;
  my $location_lookup;
  my $geolocation;
  my $program_name = $self->get_program();
  my $program;
  my $program_lookup;
  my $female_parent_cvterm = $schema->resultset("Cv::Cvterm")
    ->create_with( { name   => 'female_parent',
		     cv     => 'stock relationship',
		     db     => 'null',
		     dbxref => 'female_parent',
		   });
  my $male_parent_cvterm = $schema->resultset("Cv::Cvterm")
    ->create_with({ name   => 'male_parent',
		    cv     => 'stock relationship',
		    db     => 'null',
		    dbxref => 'male_parent',
		  });
   my $progeny_cvterm = $schema->resultset("Cv::Cvterm")
     ->create_with({ name   => 'offspring_of',
   		    cv     => 'stock relationship',
   		    db     => 'null',
   		    dbxref => 'offspring_of',
   		  });
  my $cross_name_cvterm = $schema->resultset("Cv::Cvterm")->find(
      { name   => 'cross_name',
    });

  if (!$cross_name_cvterm) {
    $cross_name_cvterm = $schema->resultset("Cv::Cvterm")
      ->create_with( { name   => 'cross_name',
		       cv     => 'local',
		       db     => 'null',
		       dbxref => 'cross_name',
		     });
  }

  my $cross_type_cvterm = $schema->resultset("Cv::Cvterm")->find(
      { name   => 'cross_type',
    });

  if (!$cross_type_cvterm) {
    $cross_type_cvterm = $schema->resultset("Cv::Cvterm")
      ->create_with( { name   => 'cross_type',
		       cv     => 'local',
		       db     => 'null',
		       dbxref => 'cross_type',
		     });
  }

  my $cross_experiment_type_cvterm = $schema->resultset('Cv::Cvterm')
    ->create_with({
		   name   => 'cross_experiment',
		   cv     => 'experiment type',
		   db     => 'null',
		   dbxref => 'cross_experiment',
		  });

  my $cross_stock_type_cvterm = $schema->resultset("Cv::Cvterm")
    ->create_with({
		   name   => 'cross',
		   cv     => 'stock type',
		  });

  if (!$self->validate_crosses()) {
    print STDERR "Invalid pedigrees in array.  No crosses will be added\n";
    return;
  }

  $location_lookup = CXGN::Location::LocationLookup->new({ schema => $schema, location_name => $self->get_location });
  $geolocation = $location_lookup->get_geolocation();

  $program_lookup = CXGN::BreedersToolbox::Projects->new({ schema => $schema});
  $program = $program_lookup->get_breeding_program_by_name($program_name);

  @crosses = @{$self->get_crosses()};

  foreach my $pedigree (@crosses) {
    my $experiment;
    my $cross_stock;
    my $organism_id;
    my $female_parent_name;
    my $male_parent_name;
    my $female_parent;
    my $male_parent;
    my $population_stock;
    my $project;
    my $cross_type = $pedigree->get_cross_type();
    my $cross_name = $pedigree->get_name();

    if ($pedigree->has_female_parent()) {
      $female_parent_name = $pedigree->get_female_parent()->get_name();
      $female_parent = $self->_get_accession($female_parent_name);
    }

    if ($pedigree->has_male_parent()) {
      $male_parent_name = $pedigree->get_male_parent()->get_name();
      $male_parent = $self->_get_accession($male_parent_name);
    }

    #organism of cross experiment will be the same as the female parent
    if ($female_parent) {
      $organism_id = $female_parent->organism_id();
    } else {
      $organism_id = $male_parent->organism_id();
    }

    #create cross project
    $project = $schema->resultset('Project::Project')
    ->create({
	      name => $cross_name,
	      description => $cross_name,
	     });

    #add error if cross name exists

    #create cross experiment
    $experiment = $schema->resultset('NaturalDiversity::NdExperiment')->create(
            {
                nd_geolocation_id => $geolocation->nd_geolocation_id(),
                type_id => $cross_experiment_type_cvterm->cvterm_id(),
            } );

    #store the cross name as an experiment prop
    $experiment->find_or_create_related('nd_experimentprops' , {
								nd_experiment_id => $experiment->nd_experiment_id(),
								type_id  =>  $cross_name_cvterm->cvterm_id(),
								value  =>  $cross_name,
							       });

    #store the cross type as an experiment prop
    $experiment->find_or_create_related('nd_experimentprops' , {
								nd_experiment_id => $experiment->nd_experiment_id(),
								type_id  =>  $cross_type_cvterm->cvterm_id(),
								value  =>  $cross_type,
							       });

    #link the parents to the experiment
    if ($female_parent) {
      $experiment->find_or_create_related('nd_experiment_stocks' , {
								    stock_id => $female_parent->stock_id(),
								    type_id  =>  $female_parent_cvterm->cvterm_id(),
								   });
    }
    if ($male_parent) {
      $experiment->find_or_create_related('nd_experiment_stocks' , {
								    stock_id => $male_parent->stock_id(),
								    type_id  =>  $male_parent_cvterm->cvterm_id(),
								   });
    }

    #create a stock of type cross
    $cross_stock = $schema->resultset("Stock::Stock")->find_or_create(
             { organism_id => $organism_id,
     	      name       => $cross_name,
     	      uniquename => $cross_name,
     	      type_id => $cross_stock_type_cvterm->cvterm_id,
             } );

    #link parents to the stock of type cross
    $cross_stock
      ->find_or_create_related('stock_relationship_objects', {
							      type_id => $female_parent_cvterm->cvterm_id(),
							      object_id => $cross_stock->stock_id(),
							      subject_id => $female_parent->stock_id(),
							     } );
    $cross_stock
      ->find_or_create_related('stock_relationship_objects', {
							      type_id => $male_parent_cvterm->cvterm_id(),
							      object_id => $cross_stock->stock_id(),
							      subject_id => $male_parent->stock_id(),
							     } );

    #link the stock of type cross to the experiment
    $experiment->find_or_create_related('nd_experiment_stocks' , {
								  stock_id => $cross_stock->stock_id(),
								  type_id  =>  $progeny_cvterm->cvterm_id(),
								 });
    #link the experiment to the project
    $experiment->find_or_create_related('nd_experiment_projects', {
								   project_id => $project->project_id()
								  } );

    #link the cross program to the breeding program
    $program_lookup->associate_breeding_program_with_trial($program->project_id(), $project->project_id());


  }

  return 1;
}


sub validate_crosses {
  my $self = shift;
  my $schema = $self->get_schema();
  my $program_name = $self->get_program();
  my $location = $self->get_location();
  my @crosses = @{$self->get_crosses()};
  my $invalid_cross_count = 0;
  my $program;

  my $location_lookup;
  my $trial_lookup;
  my $program_lookup;
  my $geolocation;

  $location_lookup = CXGN::Location::LocationLookup->new({ schema => $schema, location_name => $location });
  $geolocation = $location_lookup->get_geolocation();

  if (!$geolocation) {
    print STDERR "Location $location 2not found\n";
    return;
  }

  $program_lookup = CXGN::BreedersToolbox::Projects->new({ schema => $schema});
  $program = $program_lookup->get_breeding_program_by_name($program_name);
  if (!$program) {
    print STDERR "Breeding program $program_name not found\n";
    return;
  }

  foreach my $cross (@crosses) {
    my $validated_cross = $self->_validate_cross($cross);

    if (!$validated_cross) {
      $invalid_cross_count++;
    }

  }

  if ($invalid_cross_count > 0) {
    print STDERR "There were $invalid_cross_count invalid crosses\n";
    return;
  }

  return 1;
}

sub _validate_cross {
  my $self = shift;
  my $pedigree = shift;
  my $schema = $self->get_schema();
  my $name = $pedigree->get_name();
  my $cross_type = $pedigree->get_cross_type();
  my $female_parent_name;
  my $male_parent_name;
  my $female_parent;
  my $male_parent;

  if ($cross_type eq "biparental") {
    $female_parent_name = $pedigree->get_female_parent()->get_name();
    $male_parent_name = $pedigree->get_male_parent()->get_name();
    $female_parent = $self->_get_accession($female_parent_name);
    $male_parent = $self->_get_accession($male_parent_name);

    if (!$female_parent || !$male_parent) {
      print STDERR "Parent $female_parent_name or $male_parent_name in pedigree is not a stock\n";
      return;
    }

  } elsif ($cross_type eq "self") {
    $female_parent_name = $pedigree->get_female_parent()->get_name();
    $female_parent = $self->_get_accession($female_parent_name);

    if (!$female_parent) {
      print STDERR "Parent $female_parent_name in pedigree is not a stock\n";
      return;
    }

  }

  #add support for other cross types here

  else {
    return;
  }

  return 1;
}

sub _get_accession {
  my $self = shift;
  my $accession_name = shift;
  my $schema = $self->get_schema();
  my $stock_lookup = CXGN::Stock::StockLookup->new(schema => $schema);
  my $stock;
  my $accession_cvterm = $schema->resultset("Cv::Cvterm")
    ->create_with({
		   name   => 'accession',
		   cv     => 'stock type',
		   db     => 'null',
		   dbxref => 'accession',
		  });
  $stock_lookup->set_stock_name($accession_name);
  $stock = $stock_lookup->get_stock_exact();

  if (!$stock) {
    print STDERR "Name in pedigree is not a stock\n";
    return;
  }

  if ($stock->type_id() != $accession_cvterm->cvterm_id()) {
    print STDERR "Name in pedigree is not a stock of type accession\n";
    return;
  }

  return $stock;
}

#######
1;
#######
