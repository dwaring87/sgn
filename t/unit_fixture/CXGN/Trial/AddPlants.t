
use strict;

use lib 't/lib';

use Test::More;
use Data::Dumper;
use SGN::Test::Fixture;
use CXGN::Trial::TrialLayout;
use CXGN::Trial;
use CXGN::Trial::Download;
use Spreadsheet::WriteExcel;
use Spreadsheet::Read;
use CXGN::Fieldbook::DownloadTrial;

my $f = SGN::Test::Fixture->new();

my $trial_id = 137;

my $tl = CXGN::Trial::TrialLayout->new({ schema => $f->bcs_schema(), trial_id => $trial_id });

my $d = $tl->get_design();
#print STDERR Dumper($d);

my @plot_nums;
my @accessions;
my @plant_names;
my @rep_nums;
my @plot_names;
foreach my $plot_num (keys %$d) {
    push @plot_nums, $plot_num;
    push @accessions, $d->{$plot_num}->{'accession_name'};
    push @plant_names, $d->{$plot_num}->{'plant_names'};
    push @rep_nums, $d->{$plot_num}->{'rep_number'};
    push @plot_names, $d->{$plot_num}->{'plot_name'};
}
@plot_nums = sort @plot_nums;
@accessions = sort @accessions;
@plant_names = sort @plant_names;
@rep_nums = sort @rep_nums;
@plot_names = sort @plot_names;

#print STDERR Dumper \@plot_nums;
#print STDERR Dumper \@accessions;
#print STDERR Dumper \@plant_names;
#print STDERR Dumper \@rep_nums;
#print STDERR Dumper \@plot_names;

is_deeply(\@plot_nums, [
          '1',
          '10',
          '11',
          '12',
          '13',
          '14',
          '15',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9'
        ], 'check design plot_nums');

is_deeply(\@accessions, [
          'test_accession1',
          'test_accession1',
          'test_accession1',
          'test_accession2',
          'test_accession2',
          'test_accession2',
          'test_accession3',
          'test_accession3',
          'test_accession3',
          'test_accession4',
          'test_accession4',
          'test_accession4',
          'test_accession5',
          'test_accession5',
          'test_accession5'
        ], 'check design accessions');

is_deeply(\@plant_names, [
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          [],
          []
        ], "check design plant_names");

is_deeply(\@rep_nums, [
          '1',
          '1',
          '1',
          '1',
          '1',
          '2',
          '2',
          '2',
          '2',
          '2',
          '3',
          '3',
          '3',
          '3',
          '3'
        ], "check design rep_nums");

is_deeply(\@plot_names, [
          'test_trial21',
          'test_trial210',
          'test_trial211',
          'test_trial212',
          'test_trial213',
          'test_trial214',
          'test_trial215',
          'test_trial22',
          'test_trial23',
          'test_trial24',
          'test_trial25',
          'test_trial26',
          'test_trial27',
          'test_trial28',
          'test_trial29'
        ], "check design plot_names");


my $trial = CXGN::Trial->new({ bcs_schema => $f->bcs_schema(), trial_id => $trial_id });
$trial->create_plant_entities('2');

my $tl = CXGN::Trial::TrialLayout->new({ schema => $f->bcs_schema(), trial_id => $trial_id });
$d = $tl->get_design();
#print STDERR Dumper($d);

@plot_nums = ();
@accessions = ();
@plant_names = ();
@rep_nums = ();
@plot_names = ();
my @plant_names_flat;
foreach my $plot_num (keys %$d) {
    push @plot_nums, $plot_num;
    push @accessions, $d->{$plot_num}->{'accession_name'};
    push @plant_names, $d->{$plot_num}->{'plant_names'};
    push @rep_nums, $d->{$plot_num}->{'rep_number'};
    push @plot_names, $d->{$plot_num}->{'plot_name'};
}
@plot_nums = sort @plot_nums;
@accessions = sort @accessions;
@rep_nums = sort @rep_nums;
@plot_names = sort @plot_names;

foreach my $plant_name_arr_ref (@plant_names) {
    foreach (@$plant_name_arr_ref) {
        push @plant_names_flat, $_;
    }
}
@plant_names_flat = sort @plant_names_flat;

#print STDERR Dumper \@plot_nums;
#print STDERR Dumper \@accessions;
#print STDERR Dumper \@plant_names_flat;
#print STDERR Dumper \@rep_nums;
#print STDERR Dumper \@plot_names;

is_deeply(\@plot_nums, [
          '1',
          '10',
          '11',
          '12',
          '13',
          '14',
          '15',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9'
        ], "check plot_nums after plant addition");

is_deeply(\@accessions, [
          'test_accession1',
          'test_accession1',
          'test_accession1',
          'test_accession2',
          'test_accession2',
          'test_accession2',
          'test_accession3',
          'test_accession3',
          'test_accession3',
          'test_accession4',
          'test_accession4',
          'test_accession4',
          'test_accession5',
          'test_accession5',
          'test_accession5'
        ], "check accessions after plant addition");

is_deeply(\@plant_names_flat, [
          'test_trial210_plant_1',
          'test_trial210_plant_2',
          'test_trial211_plant_1',
          'test_trial211_plant_2',
          'test_trial212_plant_1',
          'test_trial212_plant_2',
          'test_trial213_plant_1',
          'test_trial213_plant_2',
          'test_trial214_plant_1',
          'test_trial214_plant_2',
          'test_trial215_plant_1',
          'test_trial215_plant_2',
          'test_trial21_plant_1',
          'test_trial21_plant_2',
          'test_trial22_plant_1',
          'test_trial22_plant_2',
          'test_trial23_plant_1',
          'test_trial23_plant_2',
          'test_trial24_plant_1',
          'test_trial24_plant_2',
          'test_trial25_plant_1',
          'test_trial25_plant_2',
          'test_trial26_plant_1',
          'test_trial26_plant_2',
          'test_trial27_plant_1',
          'test_trial27_plant_2',
          'test_trial28_plant_1',
          'test_trial28_plant_2',
          'test_trial29_plant_1',
          'test_trial29_plant_2'
        ], "check plant names");

is_deeply(\@rep_nums, [
          '1',
          '1',
          '1',
          '1',
          '1',
          '2',
          '2',
          '2',
          '2',
          '2',
          '3',
          '3',
          '3',
          '3',
          '3'
        ],"check rep nums after plant addition");

is_deeply(\@plot_names, [
          'test_trial21',
          'test_trial210',
          'test_trial211',
          'test_trial212',
          'test_trial213',
          'test_trial214',
          'test_trial215',
          'test_trial22',
          'test_trial23',
          'test_trial24',
          'test_trial25',
          'test_trial26',
          'test_trial27',
          'test_trial28',
          'test_trial29'
        ],"check plot_names after plant addition");


my $tempfile = "/tmp/test_create_trial_fieldbook_plants.xls";

my $create_fieldbook = CXGN::Fieldbook::DownloadTrial->new({
    bcs_schema => $f->bcs_schema,
    metadata_schema => $f->metadata_schema,
    phenome_schema => $f->phenome_schema,
    trial_id => $trial_id,
    tempfile => $tempfile,
    archive_path => $f->config->{archive_path},
    user_id => 41,
    user_name => "janedoe",
    data_level => 'plants',
});

my $create_fieldbook_return = $create_fieldbook->download();
ok($create_fieldbook_return, "check that download trial fieldbook returns something.");

my @contents = ReadData ($create_fieldbook_return->{'file'});

#print STDERR Dumper @contents->[0]->[0];
is_deeply(@contents->[0]->[0], {
          'parser' => 'Spreadsheet::ParseExcel',
          'sheets' => 1,
          'sheet' => {
                       'Sheet1' => 1
                     },
          'type' => 'xls',
          'version' => '0.65',
          'error' => undef
      }, "check fieldbook plant file");

my $columns = @contents->[0]->[1]->{'cell'};
#print STDERR Dumper scalar(@$columns);
ok(scalar(@$columns) == 8, "check number of col in created file.");

#print STDERR Dumper $columns;

is_deeply($columns->[1], [
            undef,
            'plot_id',
            'test_trial21_plant_1',
            'test_trial21_plant_2',
            'test_trial22_plant_1',
            'test_trial22_plant_2',
            'test_trial23_plant_1',
            'test_trial23_plant_2',
            'test_trial24_plant_1',
            'test_trial24_plant_2',
            'test_trial25_plant_1',
            'test_trial25_plant_2',
            'test_trial26_plant_1',
            'test_trial26_plant_2',
            'test_trial27_plant_1',
            'test_trial27_plant_2',
            'test_trial28_plant_1',
            'test_trial28_plant_2',
            'test_trial29_plant_1',
            'test_trial29_plant_2',
            'test_trial210_plant_1',
            'test_trial210_plant_2',
            'test_trial211_plant_1',
            'test_trial211_plant_2',
            'test_trial212_plant_1',
            'test_trial212_plant_2',
            'test_trial213_plant_1',
            'test_trial213_plant_2',
            'test_trial214_plant_1',
            'test_trial214_plant_2',
            'test_trial215_plant_1',
            'test_trial215_plant_2'
          ], "check contents of first col");

is_deeply($columns->[2], [
            undef,
            'range',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1'
          ], "check contents of second col");

is_deeply($columns->[3],[
            undef,
            'plant',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2',
            '1',
            '2'
          ], "check contents of third col");

is_deeply($columns->[4], [
            undef,
            'plot',
            '1',
            '1',
            '2',
            '2',
            '3',
            '3',
            '4',
            '4',
            '5',
            '5',
            '6',
            '6',
            '7',
            '7',
            '8',
            '8',
            '9',
            '9',
            '10',
            '10',
            '11',
            '11',
            '12',
            '12',
            '13',
            '13',
            '14',
            '14',
            '15',
            '15'
          ], "check contents of fourth col");

is_deeply($columns->[5], [
            undef,
            'rep',
            '1',
            '1',
            '1',
            '1',
            '1',
            '1',
            '2',
            '2',
            '1',
            '1',
            '2',
            '2',
            '2',
            '2',
            '2',
            '2',
            '1',
            '1',
            '3',
            '3',
            '3',
            '3',
            '3',
            '3',
            '2',
            '2',
            '3',
            '3',
            '3',
            '3'
          ], "check contents of fifth col");

is_deeply($columns->[6],[
            undef,
            'accession',
            'test_accession4',
            'test_accession4',
            'test_accession5',
            'test_accession5',
            'test_accession3',
            'test_accession3',
            'test_accession3',
            'test_accession3',
            'test_accession1',
            'test_accession1',
            'test_accession4',
            'test_accession4',
            'test_accession5',
            'test_accession5',
            'test_accession1',
            'test_accession1',
            'test_accession2',
            'test_accession2',
            'test_accession3',
            'test_accession3',
            'test_accession1',
            'test_accession1',
            'test_accession5',
            'test_accession5',
            'test_accession2',
            'test_accession2',
            'test_accession4',
            'test_accession4',
            'test_accession2',
            'test_accession2'
          ], "check contents of sixth col");

is_deeply($columns->[7],[
            undef,
            'is_a_control'
          ], "check contents of 7th col");


done_testing();



