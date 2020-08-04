use strict;

package SGN::Controller::AJAX::Nirs;

use Moose;
use Data::Dumper;
use File::Temp qw | tempfile |;
# use File::Slurp;
use File::Spec qw | catfile|;
use File::Basename qw | basename |;
use File::Copy;
use CXGN::Dataset;
use CXGN::Dataset::File;
use CXGN::Tools::Run;
use CXGN::Page::UserPrefs;
use CXGN::Tools::List qw/distinct evens/;
use CXGN::Blast::Parse;
use CXGN::Blast::SeqQuery;
# use Path::Tiny qw(path);
use Cwd qw(cwd);
use JSON::XS;
use List::Util qw(shuffle);
use CXGN::AnalysisModel::GetModel;

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
    );


sub extract_trait_data :Path('/ajax/Nirs/getdata') Args(0) {
    my $self = shift;
    my $c = shift;

    my $file = $c->req->param("file"); # where is this in the html form?
    my $trait = $c->req->param("trait");

    $file = basename($file);

    my $temppath = File::Spec->catfile($c->config->{basepath}, "static/documents/tempfiles/nirs_files/".$file);
    print STDERR Dumper($temppath);

    my $F;
    if (! open($F, "<", $temppath)) {
	$c->stash->{rest} = { error => "Can't find data." };
	return;
    }

    my $header = <$F>;
    chomp($header);
    print STDERR Dumper($header);
    my @keys = split("\t", $header);
    print STDERR Dumper($keys[1]);
    for(my $n=0; $n <@keys; $n++) {
        if ($keys[$n] =~ /\|CO\_/) {
        $keys[$n] =~ s/\|CO\_.*//;
        }
    }
    my @data = ();

    while (<$F>) {
	chomp;

	my @fields = split "\t";
	my %line = {};
	for(my $n=0; $n <@keys; $n++) {
	    if (exists($fields[$n]) && defined($fields[$n])) {
		$line{$keys[$n]}=$fields[$n];
	    }
	}
    print STDERR Dumper(\%line);
	push @data, \%line;
    }

    $c->stash->{rest} = { data => \@data, trait => $trait};

}

sub generate_results : Path('/ajax/Nirs/generate_results') : ActionClass('REST') { }
sub generate_results_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $dbh = $c->dbc->dbh();
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    print STDERR Dumper $c->req->params();

    my $format_id = $c->req->param('format');
    my $cv_scheme = $c->req->param('cv');
    my $train_dataset_id = $c->req->param('train_dataset_id');
    my $test_dataset_id = $c->req->param('test_dataset_id');
    my $train_id = $c->req->param('train_id');
    my $test_id = $c->req->param('test_id');
    my $trait_id = $c->req->param('trait_id');
    my $niter_id = $c->req->param('niter');
    my $algo_id =$c->req->param('algorithm');
    my $preprocessing_boolean = $c->req->param('preprocessing');
    my $tune_id = $c->req->param('tune');
    my $rf_var_imp = $c->req->param('rf');

    if ($preprocessing_boolean == 0){
        $preprocessing_boolean = "FALSE";
    } else {
        $preprocessing_boolean = "TRUE";
    }

    if ($rf_var_imp == 0){
        $rf_var_imp = "FALSE";
    } else {
        $rf_var_imp = "TRUE";
    }

    $c->tempfiles_subdir("nirs_files");
    my $nirs_tmp_output = $c->config->{cluster_shared_tempdir}."/nirs_files";
    mkdir $nirs_tmp_output if ! -d $nirs_tmp_output;
    my ($tmp_fh, $tempfile) = tempfile(
        "nirs_download_XXXXX",
        DIR=> $nirs_tmp_output,
    );

    my $train_json_filepath = $tempfile."_train_json";
    my $test_json_filepath = $tempfile."_test_json";

    my $output_table_filepath = $tempfile."_table_results.txt";
    my $output_figure_filepath = $tempfile."_figure_results.png";
    my $output_table2_filepath = $tempfile."_table2_results.txt";
    my $output_figure2_filepath = $tempfile."_figure2_results.png";
    my $output_model_filepath = $tempfile."_model.Rds";

    my $training_dataset = CXGN::Dataset->new({people_schema => $people_schema, schema => $schema, sp_dataset_id => $train_dataset_id});
    my ($training_pheno_data, $train_unique_traits) = $training_dataset->retrieve_phenotypes_ref();
    # print STDERR Dumper $training_pheno_data;

    my %training_pheno_data;
    my $seltrait;
    foreach my $d (@$training_pheno_data) {
        my $obsunit_id = $d->{observationunit_stock_id};
        my $germplasm_name = $d->{germplasm_uniquename};
        foreach my $o (@{$d->{observations}}) {
            my $t_id = $o->{trait_id};
            my $t_name = $o->{trait_name};
            my $value = $o->{value};
            $seltrait = $t_name;
            if ($trait_id == $t_id) {
                $training_pheno_data{$obsunit_id} = {
                    value => $value,
                    trait_id => $t_id,
                    trait_name => $t_name,
                    germplasm_name => $germplasm_name
                };
            }
        }
    }

    my %testing_pheno_data;
    if ($test_dataset_id) {
        my $test_dataset = CXGN::Dataset->new({people_schema => $people_schema, schema => $schema, sp_dataset_id => $test_dataset_id});
        my ($test_pheno_data, $test_unique_traits) = $test_dataset->retrieve_phenotypes_ref();
        # print STDERR Dumper $test_pheno_data;

        foreach my $d ($test_pheno_data) {
            my $obsunit_id = $d->{observationunit_stock_id};
            my $germplasm_name = $d->{germplasm_uniquename};
            foreach my $o (@{$d->{observations}}) {
                my $t_id = $o->{trait_id};
                my $t_name = $o->{trait_name};
                my $value = $o->{value};
                if ($trait_id == $t_id) {
                    $testing_pheno_data{$obsunit_id} = {
                        value => $value,
                        trait_id => $t_id,
                        trait_name => $t_name,
                        germplasm_name => $germplasm_name
                    };
                }
            }
        }
    }
    # else { #waves package will do random split if the input JSON = 'NULL'
    #     my @full_training_plots = keys %training_pheno_data;
    #     my $cutoff = int(scalar(@full_training_plots)*0.2);
    #     my @random_plots = shuffle(@full_training_plots);
    # 
    #     my @testing_plots = @random_plots[0..$cutoff];
    #     my @training_plots = @random_plots[$cutoff+1..scalar(@full_training_plots)-1];
    # 
    #     my %training_pheno_data_split;
    #     my %testing_pheno_data_split;
    #     foreach (@training_plots) {
    #         $training_pheno_data_split{$_} = $training_pheno_data{$_};
    #     }
    #     foreach (@testing_plots) {
    #         $testing_pheno_data_split{$_} = $training_pheno_data{$_};
    #     }
    #     %training_pheno_data = %training_pheno_data_split;
    #     %testing_pheno_data = %testing_pheno_data_split;
    # }

    my @all_plot_ids = (keys %training_pheno_data, keys %testing_pheno_data);
    my $stock_ids_sql = join ',', @all_plot_ids;
    my $nirs_training_q = "SELECT stock.uniquename, stock.stock_id, metadata.md_json.json->>'spectra'
        FROM stock
        JOIN nd_experiment_stock USING(stock_id)
        JOIN nd_experiment USING(nd_experiment_id)
        JOIN phenome.nd_experiment_md_json USING(nd_experiment_id)
        JOIN metadata.md_json USING(json_id)
        WHERE stock.stock_id IN ($stock_ids_sql) AND metadata.md_json.json->>'device_type' = ? ;";
    my $nirs_training_h = $dbh->prepare($nirs_training_q);    
    $nirs_training_h->execute($format_id);
    while (my ($stock_uniquename, $stock_id, $spectra) = $nirs_training_h->fetchrow_array()) {
        $spectra = decode_json $spectra;
        if (exists($training_pheno_data{$stock_id})) {
            $training_pheno_data{$stock_id}->{spectra} = $spectra;
        }
        if (exists($testing_pheno_data{$stock_id})) {
            $testing_pheno_data{$stock_id}->{spectra} = $spectra;
        }
    }
    # print STDERR Dumper \%training_pheno_data;
    # print STDERR Dumper \%testing_pheno_data;

    my @training_data_input;
    while ( my ($stock_id, $o) = each %training_pheno_data) {
        my $trait_name = $o->{trait_name};
        my $value = $o->{value};
        my $spectra = $o->{spectra};
        my $germplasm_name = $o->{germplasm_name};
        if ($spectra && $value) {
            push @training_data_input, {
                "observationUnitId" => $stock_id,
                "germplasmName" => $germplasm_name,
                "trait" => {$trait_name => $value},
                "nirs_spectra" => $spectra
            };
        }
    }
    my $training_data_input_json = encode_json \@training_data_input;
    open(my $train_json_outfile, '>', $train_json_filepath);
        print STDERR Dumper $train_json_filepath;
        print $train_json_outfile $training_data_input_json;
    close($train_json_outfile);

    my @testing_data_input;
    while ( my ($stock_id, $o) = each %testing_pheno_data) {
        my $trait_name = $o->{trait_name};
        my $value = $o->{value};
        my $spectra = $o->{spectra};
        my $germplasm_name = $o->{germplasm_name};
        if ($spectra && $value) {
            push @testing_data_input, {
                "observationUnitId" => $stock_id,
                "germplasmName" => $germplasm_name,
                "trait" => {$trait_name => $value},
                "nirs_spectra" => $spectra
            };
        }
    }
    my $testing_data_input_json;
    if (scalar(@testing_data_input) == 0) {
        # $testing_data_input_json = 'NULL';
        $test_json_filepath = 'NULL';
    }
    else {
        $testing_data_input_json = encode_json \@testing_data_input;

        open(my $test_json_outfile, '>', $test_json_filepath);
            print STDERR Dumper $test_json_filepath;
            print $test_json_outfile $testing_data_input_json;
        close($test_json_outfile);
    }

    my $trial1_filepath = '';
    my $trial2_filepath = '';
    my $trial3_filepath = '';

    # my $cmd = CXGN::Tools::Run->new({
    #         backend => $c->config->{backend},
    #         temp_base => $c->config->{cluster_shared_tempdir} . "/nirs_files",
    #         queue => $c->config->{'web_cluster_queue'},
    #         do_cleanup => 0,
    #         # don't block and wait if the cluster looks full
    #         max_cluster_jobs => 1_000_000_000,
    #     });
    # 
    #     # print STDERR Dumper $pheno_filepath;
    # 
    # # my $job;
    # $cmd->run_cluster(
    #         "Rscript ",
    #         $c->config->{basepath} . "/R/Nirs/nirs.R",
    #         $seltrait, # args[1]
    #         $preprocessing_boolean, # args[2]
    #         $niter_id, # args[3]
    #         $algo_id, # args[4]
    #         $tune_id, # args[5]
    #         $rf_var_imp, # args[6]
    #         $cv_scheme, # args[7]
    #         $train_json_filepath, # args[8]
    #         $test_json_filepath, # args[9]
    #         $trial1_filepath, # args[10]
    #         $trial2_filepath, # args[11]
    #         $trial3_filepath, # args[12]
    #         $output_result_filepath # args[13]
    # );
    # $cmd->alive;
    # $cmd->is_cluster(1);
    # $cmd->wait;

    my $cmd_s = "Rscript ".$c->config->{basepath} . "/R/Nirs/nirs.R '$seltrait' '$preprocessing_boolean' '$niter_id' '$algo_id' '$tune_id' '$rf_var_imp' '$cv_scheme' '$train_json_filepath' '$test_json_filepath' 'TRUE' '$output_model_filepath' '$output_table2_filepath' '$output_figure2_filepath' '$output_table_filepath' '$output_figure_filepath' ";
    print STDERR $cmd_s;
    my $cmd_status = system($cmd_s);

    $c->stash->{rest} = {
        train_dataset_id => $train_dataset_id,
        model_properties => {
            'trait_id' => $trait_id,
            'trait_name' => $seltrait,
            'preprocessing_boolean' => $preprocessing_boolean,
            'niter' => $niter_id,
            'algorithm' => $algo_id,
            'tune' => $tune_id,
            'random_forest_importance' => $rf_var_imp,
            'cross_validation' => $cv_scheme,
            'format' => $format_id
        },
        model_file => $output_model_filepath,
        model_file_type => "jennasrwaves_V1.01_waves_nirs_spectral_predictions_weights_file",
        training_data_file => $train_json_filepath,
        model_aux_files => [
            {"jennasrwaves_V1.01_waves_nirs_spectral_predictions_testing_data_file" => $test_json_filepath},
            {"jennasrwaves_V1.01_waves_nirs_spectral_predictions_performance_output" => $output_table_filepath}
        ]
    };
}

sub generate_predictions : Path('/ajax/Nirs/generate_predictions') : ActionClass('REST') { }
sub generate_predictions_POST : Args(0) {
    my $self = shift;
    my $c = shift;
    my $dbh = $c->dbc->dbh();
    my $people_schema = $c->dbic_schema("CXGN::People::Schema");
    my $metadata_schema = $c->dbic_schema("CXGN::Metadata::Schema");
    my $phenome_schema = $c->dbic_schema("CXGN::Phenome::Schema");
    my $schema = $c->dbic_schema("Bio::Chado::Schema", "sgn_chado");
    print STDERR Dumper $c->req->params();

    my $model_id = $c->req->param('model_id');
    my $dataset_id = $c->req->param('dataset_id');

    my $m = CXGN::AnalysisModel::GetModel->new({
        bcs_schema=>$schema,
        metadata_schema=>$metadata_schema,
        phenome_schema=>$phenome_schema,
        nd_protocol_id=>$model_id
    });
    my $saved_model_object = $m->get_model();
    print STDERR Dumper $saved_model_object;
    my $trait_name = $saved_model_object->{model_properties}->{trait_name};
    my $trait_id = $saved_model_object->{model_properties}->{trait_id};
    my $format_id = $saved_model_object->{model_properties}->{format};
    my $model_file = $saved_model_object->{model_files}->{"jennasrwaves_V1.01_waves_nirs_spectral_predictions_weights_file"};

    my $training_dataset = CXGN::Dataset->new({people_schema => $people_schema, schema => $schema, sp_dataset_id => $dataset_id});
    my ($training_pheno_data, $train_unique_traits) = $training_dataset->retrieve_phenotypes_ref();
    # print STDERR Dumper $training_pheno_data;

    my %training_pheno_data;
    my $seltrait;
    foreach my $d (@$training_pheno_data) {
        my $obsunit_id = $d->{observationunit_stock_id};
        my $germplasm_name = $d->{germplasm_uniquename};
        foreach my $o (@{$d->{observations}}) {
            my $t_id = $o->{trait_id};
            my $t_name = $o->{trait_name};
            my $value = $o->{value};
            $seltrait = $t_name;
            if ($trait_id == $t_id) {
                $training_pheno_data{$obsunit_id} = {
                    value => $value,
                    trait_id => $t_id,
                    trait_name => $t_name,
                    germplasm_name => $germplasm_name
                };
            }
        }
    }

    my @all_plot_ids = keys %training_pheno_data;
    my $stock_ids_sql = join ',', @all_plot_ids;
    my $nirs_training_q = "SELECT stock.uniquename, stock.stock_id, metadata.md_json.json->>'spectra'
        FROM stock
        JOIN nd_experiment_stock USING(stock_id)
        JOIN nd_experiment USING(nd_experiment_id)
        JOIN phenome.nd_experiment_md_json USING(nd_experiment_id)
        JOIN metadata.md_json USING(json_id)
        WHERE stock.stock_id IN ($stock_ids_sql) AND metadata.md_json.json->>'device_type' = ? ;";
    my $nirs_training_h = $dbh->prepare($nirs_training_q);    
    $nirs_training_h->execute($format_id);
    while (my ($stock_uniquename, $stock_id, $spectra) = $nirs_training_h->fetchrow_array()) {
        $spectra = decode_json $spectra;
        if (exists($training_pheno_data{$stock_id})) {
            $training_pheno_data{$stock_id}->{spectra} = $spectra;
        }
    }
    # print STDERR Dumper \%training_pheno_data;

    my @training_data_input;
    while ( my ($stock_id, $o) = each %training_pheno_data) {
        my $trait_name = $o->{trait_name};
        my $value = $o->{value};
        my $spectra = $o->{spectra};
        my $germplasm_name = $o->{germplasm_name};
        if ($spectra && $value) {
            push @training_data_input, {
                "observationUnitId" => $stock_id,
                "germplasmName" => $germplasm_name,
                "trait" => {$trait_name => $value},
                "nirs_spectra" => $spectra
            };
        }
    }

    if (scalar(@training_data_input) == 0) {
        $c->stash->{rest} = { error => "There is no NIRs using $format_id and phenotype data for $trait_name through the dataset selected!" };
        $c->detach();
    }

    $c->tempfiles_subdir("nirs_files");
    my $nirs_tmp_output = $c->config->{cluster_shared_tempdir}."/nirs_files";
    mkdir $nirs_tmp_output if ! -d $nirs_tmp_output;
    my ($tmp_fh, $tempfile) = tempfile(
        "nirs_download_XXXXX",
        DIR=> $nirs_tmp_output,
    );

    my $input_json_filepath = $tempfile."_train_json";
    my $output_table_filepath = $tempfile."_table_results.txt";
    my $output_figure_filepath = $tempfile."_figure_results.png";
    
    my $training_data_input_json = encode_json \@training_data_input;
    open(my $train_json_outfile, '>', $input_json_filepath);
        print STDERR Dumper $input_json_filepath;
        print $train_json_outfile $training_data_input_json;
    close($train_json_outfile);

    my $cmd_s = "Rscript ".$c->config->{basepath} . "/R/Nirs/nirsPredict.R '$seltrait' '$input_json_filepath' '$model_file' '$output_table_filepath' '$output_figure_filepath' ";
    print STDERR $cmd_s;
    my $cmd_status = system($cmd_s);

    $c->stash->{rest} = { success => 1 };
}

1
