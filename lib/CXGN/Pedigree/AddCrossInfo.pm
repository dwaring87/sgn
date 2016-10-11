package CXGN::Pedigree::AddCrossInfo;

=head1 NAME

CXGN::Pedigree::AddCrossInfo - a module to add information such as number of seeds or number of flowers to cross experiments.

=head1 USAGE

 my $cross_add_info = CXGN::Pedigree::AddCrossInfo->new({ schema => $schema, cross_name => $cross_name} );
 $cross_add_info->set_number_of_seeds($number_of_seeds);
 $cross_add_info->add_info();


=head1 DESCRIPTION

Adds experiment properties to cross experiment. The a stock of type cross is found using the specified cross name.  Tthe cross must already exist in the database.   This module is intended to be used in independent loading scripts and interactive dialogs.

=head1 AUTHORS

 Jeremy D. Edwards (jde22@cornell.edu)

=cut

use Moose;
use MooseX::FollowPBP;
use Moose::Util::TypeConstraints;
use Try::Tiny;
use CXGN::Stock::StockLookup;
use SGN::Model::Cvterm;

has 'chado_schema' => (
		 is       => 'rw',
		 isa      => 'DBIx::Class::Schema',
		 predicate => 'has_chado_schema',
		 required => 1,
		);
has 'cross_name' => (isa =>'Str', is => 'rw', predicate => 'has_cross_name', required => 1,);
has 'info_type' => (isa =>'Str', is => 'rw', predicate => 'has_info_type', required => 1,);
has 'value' => (isa =>'Str', is => 'rw', predicate => 'has_value', required => 1,);


sub add_info {
  my $self = shift;
  my $schema = $self->get_chado_schema();
  my $transaction_error;

  #add all cross info in a single transaction
  my $coderef = sub {


    #get cross (stock of type cross)
    my $cross_stock = $self->_get_cross($self->get_cross_name());
    if (!$cross_stock) {
      print STDERR "Cross could not be found\n";
      return;
    }


    #get experiment
    my $experiment = $schema->resultset('NaturalDiversity::NdExperiment')
      ->find({
	      'nd_experiment_stocks.stock_id' => $cross_stock->stock_id,
	     },
	     {
	      join => 'nd_experiment_stocks',
	     });
    if (!$experiment) {
      print STDERR "Cross experiment could not be found\n";
      return;
    }

		#print STDERR "Adding info type: " . $self->get_info_type() . " value: " . $self->get_value() . "\n";
    my $info_type_cvterm = SGN::Model::Cvterm->get_cvterm_row($schema, $self->get_info_type(), 'nd_experiment_property');

		$experiment->find_or_create_related('nd_experimentprops' , {
	      nd_experiment_id => $experiment->nd_experiment_id(),
	      type_id  =>  $info_type_cvterm->cvterm_id(),
	      value  =>  $self->get_value(),
		});

  };

  #try to add all cross info in a transaction
  try {
    $schema->txn_do($coderef);
  } catch {
    $transaction_error =  $_;
  };

  if ($transaction_error) {
    print STDERR "Transaction error storing information for cross: $transaction_error\n";
    return;
  }

  return 1;
}



sub _get_cross {
  my $self = shift;
  my $cross_name = shift;
  my $schema = $self->get_chado_schema();
  my $stock_lookup = CXGN::Stock::StockLookup->new(schema => $schema);
  my $stock;
  my $cross_cvterm =  SGN::Model::Cvterm->get_cvterm_row($schema, 'cross', 'stock_type');

  $stock_lookup->set_stock_name($cross_name);
  $stock = $stock_lookup->get_stock_exact();

  if (!$stock) {
    print STDERR "Cross name does not exist\n";
    return;
  }

  if ($stock->type_id() != $cross_cvterm->cvterm_id()) {
    print STDERR "Cross name is not a stock of type cross\n";
    return;
  }

  return $stock;
}

#######
1;
#######
