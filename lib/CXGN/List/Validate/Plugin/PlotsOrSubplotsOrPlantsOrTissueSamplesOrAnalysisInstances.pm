
package CXGN::List::Validate::Plugin::PlotsOrSubplotsOrPlantsOrTissueSamplesOrAnalysisInstances;

use Moose;
use SGN::Model::Cvterm;

sub name {
    return "plots_or_subplots_or_plants_or_tissue_samples_or_analysis_instances";
}

sub validate {
    my $self = shift;
    my $schema = shift;
    my $list = shift;

    my $plant_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plant', 'stock_type')->cvterm_id();
    my $plot_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'plot', 'stock_type')->cvterm_id();
    my $subplot_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'subplot', 'stock_type')->cvterm_id();
    my $tissue_sample_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'tissue_sample', 'stock_type')->cvterm_id();
    my $analysis_instance_type_id = SGN::Model::Cvterm->get_cvterm_row($schema, 'analysis_instance', 'stock_type')->cvterm_id();

    my @missing = ();
    foreach my $l (@$list) {
        my $rs = $schema->resultset("Stock::Stock")->search({
            type_id=> [$plot_type_id, $plant_type_id, $subplot_type_id, $tissue_sample_type_id, $analysis_instance_type_id],
            uniquename => $l,
        });
        if ($rs->count() == 0) {
            push @missing, $l;
        }
    }
    return { missing => \@missing };
}

1;
