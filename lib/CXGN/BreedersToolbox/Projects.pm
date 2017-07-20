
package CXGN::BreedersToolbox::Projects;

use Moose;
use Data::Dumper;
use SGN::Model::Cvterm;
use CXGN::People::Roles;

has 'schema' => (
		 is       => 'rw',
		 isa      => 'DBIx::Class::Schema',
		);


sub trial_exists {
    my $self = shift;
    my $trial_id = shift;

    my $rs = $self->schema->resultset('Project::Project')->search( { project_id => $trial_id });

    if ($rs->count() == 0) {
	return 0;
    }
    return 1;
}

sub get_breeding_programs {
    my $self = shift;


    my $breeding_program_cvterm_id = $self->get_breeding_program_cvterm_id();

    my $rs = $self->schema->resultset('Project::Project')->search( { 'projectprops.type_id'=>$breeding_program_cvterm_id }, { join => 'projectprops' }  );

    my @projects;
    while (my $row = $rs->next()) {
	push @projects, [ $row->project_id, $row->name, $row->description ];
    }

    return \@projects;
}

# deprecated. Use CXGN::Trial->get_breeding_program instead.
sub get_breeding_programs_by_trial {
    my $self = shift;
    my $trial_id = shift;

    my $breeding_program_cvterm_id = $self->get_breeding_program_cvterm_id();

    my $trial_rs= $self->schema->resultset('Project::ProjectRelationship')->search( { 'subject_project_id' => $trial_id } );

    my $trial_row = $trial_rs -> first();
    my $rs;
    my @projects;

    if ($trial_row) {
	$rs = $self->schema->resultset('Project::Project')->search( { 'me.project_id' => $trial_row->object_project_id(), 'projectprops.type_id'=>$breeding_program_cvterm_id }, { join => 'projectprops' }  );

	while (my $row = $rs->next()) {
	    push @projects, [ $row->project_id, $row->name, $row->description ];
	}
    }
    return  \@projects;
}



sub get_breeding_program_by_name {
  my $self = shift;
  my $program_name = shift;
  my $breeding_program_cvterm_id = $self->get_breeding_program_cvterm_id();

  my $rs = $self->schema->resultset('Project::Project')->find( { 'name'=>$program_name, 'projectprops.type_id'=>$breeding_program_cvterm_id }, { join => 'projectprops' }  );

  if (!$rs) {
    return;
  }
  print STDERR "**Projects.pm: found program_name $program_name id = " . $rs->project_id . "\n\n";

  return $rs;

}

sub _get_all_trials_by_breeding_program {
    my $self = shift;
    my $breeding_project_id = shift;
    my $dbh = $self->schema->storage->dbh();
    my $breeding_program_cvterm_id = $self->get_breeding_program_cvterm_id();

    my $trials = [];
    my $h;
    if ($breeding_project_id) {
	# need to convert to dbix class.... good luck!
	#my $q = "SELECT trial.project_id, trial.name, trial.description FROM project LEFT join project_relationship ON (project.project_id=object_project_id) LEFT JOIN project as trial ON (subject_project_id=trial.project_id) LEFT JOIN projectprop ON (trial.project_id=projectprop.project_id) WHERE (project.project_id=? AND (projectprop.type_id IS NULL OR projectprop.type_id != ?))";
	my $q = "SELECT trial.project_id, trial.name, trial.description, projectprop.type_id, projectprop.value FROM project LEFT join project_relationship ON (project.project_id=object_project_id) LEFT JOIN project as trial ON (subject_project_id=trial.project_id) LEFT JOIN projectprop ON (trial.project_id=projectprop.project_id) WHERE (project.project_id = ?)";

	$h = $dbh->prepare($q);
	#$h->execute($breeding_project_id, $cross_cvterm_id);
	$h->execute($breeding_project_id);

    }
    else {
	# get trials that are not associated with any project
	my $q = "SELECT project.project_id, project.name, project.description , projectprop.type_id, projectprop.value FROM project JOIN projectprop USING(project_id) LEFT JOIN project_relationship ON (subject_project_id=project.project_id) WHERE project_relationship_id IS NULL and projectprop.type_id != ?";
	$h = $dbh->prepare($q);
	$h->execute($breeding_program_cvterm_id);
    }

    return $h;
}

sub get_trials_by_breeding_program {
    my $self = shift;
    my $breeding_project_id = shift;
    my $field_trials;
    my $cross_trials;
    my $genotyping_trials;
    my $h = $self->_get_all_trials_by_breeding_program($breeding_project_id);
    my $cross_cvterm_id = $self->get_cross_cvterm_id();
    my $project_year_cvterm_id = $self->get_project_year_cvterm_id();

    my %projects_that_are_crosses;
    my %project_year;
    my %project_name;
    my %project_description;
    my %projects_that_are_genotyping_trials;

    while (my ($id, $name, $desc, $prop, $propvalue) = $h->fetchrow_array()) {
	#print STDERR "PROP: $prop, $propvalue \n";
	#push @$trials, [ $id, $name, $desc ];
      if ($name) {
	$project_name{$id} = $name;
      }
      if ($desc) {
	$project_description{$id} = $desc;
      }
      if ($prop) {
	if ($prop == $cross_cvterm_id) {
	  $projects_that_are_crosses{$id} = 1;
	  $project_year{$id} = '';
	  #print STDERR Dumper "Cross Trial: ".$name;
	}
	if ($prop == $project_year_cvterm_id) {
	  $project_year{$id} = $propvalue;
	}
	if ($propvalue) {
	if ($propvalue eq "genotyping_plate") {
	    #print STDERR "$id IS GENOTYPING TRIAL\n";
	    $projects_that_are_genotyping_trials{$id} =1;
		#print STDERR Dumper "Genotyping Trial: ".$name;
	}
	}
      }

    }

    my @sorted_by_year_keys = sort { $project_year{$a} cmp $project_year{$b} } keys(%project_year);

    foreach my $id_key (@sorted_by_year_keys) {
		if (!$projects_that_are_crosses{$id_key} && !$projects_that_are_genotyping_trials{$id_key}) {
			#print STDERR "$id_key RETAINED.\n";
			push @$field_trials, [ $id_key, $project_name{$id_key}, $project_description{$id_key}];
		} elsif ($projects_that_are_crosses{$id_key} == 1) {
			push @$cross_trials, [ $id_key, $project_name{$id_key}, $project_description{$id_key}];
		} elsif ($projects_that_are_genotyping_trials{$id_key} == 1) {
			push @$genotyping_trials, [ $id_key, $project_name{$id_key}, $project_description{$id_key}];
		}
    }

    return ($field_trials, $cross_trials, $genotyping_trials);
}

sub get_genotyping_trials_by_breeding_program {
    my $self = shift;
    my $breeding_project_id = shift;
    my $trials;
    my $h = $self->_get_all_trials_by_breeding_program($breeding_project_id);
    my $cross_cvterm_id = $self->get_cross_cvterm_id();
    my $project_year_cvterm_id = $self->get_project_year_cvterm_id();

    my %projects_that_are_crosses;
    my %projects_that_are_genotyping_trials;
    my %project_year;
    my %project_name;
    my %project_description;

    while (my ($id, $name, $desc, $prop, $propvalue) = $h->fetchrow_array()) {
	if ($name) {
	    $project_name{$id} = $name;
	}
	if ($desc) {
	    $project_description{$id} = $desc;
	}
	if ($prop) {
	    if ($prop == $cross_cvterm_id) {
		$projects_that_are_crosses{$id} = 1;
	    }
	    if ($prop == $project_year_cvterm_id) {
		$project_year{$id} = $propvalue;
	    }

	    if ($propvalue eq "genotyping_plate") {
		$projects_that_are_genotyping_trials{$id} = 1;
	    }
	}

    }

    my @sorted_by_year_keys = sort { $project_year{$a} cmp $project_year{$b} } keys(%project_year);

    foreach my $id_key (@sorted_by_year_keys) {
      if (!$projects_that_are_crosses{$id_key}) {
	if ($projects_that_are_genotyping_trials{$id_key}) {
	  push @$trials, [ $id_key, $project_name{$id_key}, $project_description{$id_key}];
	}
      }
    }

    return $trials;

}

sub get_all_locations {
    my $self = shift;

    my $project_location_type_id = $self ->schema->resultset('Cv::Cvterm')->search( { 'name' => 'project location' })->first->cvterm_id();

	my $q = "SELECT geo.nd_geolocation_id,
	geo.description,
	abbreviation.value,
	country_code.value,
	breeding_program.name,
	location_type.value,
	longitude,
	latitude,
	altitude,
    count(distinct(projectprop.project_id))
FROM nd_geolocation AS geo
LEFT JOIN nd_geolocationprop AS abbreviation ON (geo.nd_geolocation_id = abbreviation.nd_geolocation_id AND abbreviation.type_id = (SELECT cvterm_id from cvterm where name = 'abbreviation') )
LEFT JOIN nd_geolocationprop AS country_code ON (geo.nd_geolocation_id = country_code.nd_geolocation_id AND country_code.type_id = (SELECT cvterm_id from cvterm where name = 'country_code') )
LEFT JOIN nd_geolocationprop AS location_type ON (geo.nd_geolocation_id = location_type.nd_geolocation_id AND location_type.type_id = (SELECT cvterm_id from cvterm where name = 'location_type') )
LEFT JOIN projectprop ON (projectprop.value::INT = geo.nd_geolocation_id AND projectprop.type_id=?)
LEFT JOIN project AS trial ON (trial.project_id=projectprop.project_id)
LEFT JOIN project_relationship ON (subject_project_id=trial.project_id)
LEFT JOIN project breeding_program ON (breeding_program.project_id=object_project_id)
GROUP BY 1,2,3,4,5,6
ORDER BY 8,2";


	my $h = $self->schema()->storage()->dbh()->prepare($q);
	$h->execute($project_location_type_id);
#
    my @locations;
    while (my ($id, $name, $abbrev, $country_code, $prog, $type, $longitude, $latitude, $altitude, $trial_count) = $h->fetchrow_array()) {
        $name = '<font id="'.$id.'_name">'.$name.'</font>';
        $abbrev = '<font id="'.$id.'_abbrev">'.$abbrev.'</font>';
        $country_code = '<font id="'.$id.'_country">'.$country_code.'</font>';
        $prog = '<font id="'.$id.'_prog">'.$prog.'</font>';
        $type = '<font id="'.$id.'_type">'.$type.'</font>';
        $latitude = '<font id="'.$id.'_lat">'.$latitude.'</font>';
        $longitude = '<font id="'.$id.'_long">'.$longitude.'</font>';
        $altitude = '<font id="'.$id.'_alt">'.$altitude.'</font>';
        $trial_count = '<font id="'.$id.'_count">'.$trial_count.'</font>';
        my $edit_link = "<a href=\"javascript:edit_location($id)\"><font style=\"color: blue; font-weight: bold\">Edit</a>";
        my $delete_link;
        if ($trial_count == 0) {
            $delete_link = '<a title="Delete" id="'.$id.'_remove" href="javascript:delete_location('.$id.')"><span style="color: red" class="glyphicon glyphicon-remove"></span></a>';
        } else {
            $delete_link = '<a title="Unable to delete locations that are linked to one or more trials" id="'.$id.'_remove"><span class="glyphicon glyphicon-remove"></span></a>';
        }
        push @locations, [$name, $abbrev, $country_code, $prog, $type, $longitude, $latitude, $altitude, $trial_count, $edit_link, $delete_link];
    }
    return \@locations;
}

sub get_locations {
    my $self = shift;

    my @rows = $self->schema()->resultset('NaturalDiversity::NdGeolocation')->all();

    my $type_id = $self->schema()->resultset('Cv::Cvterm')->search( { 'name'=>'plot' })->first->cvterm_id;


    my @locations = ();
    foreach my $row (@rows) {
	my $plot_count = "SELECT count(*) from stock join cvterm on(type_id=cvterm_id) join nd_experiment_stock using(stock_id) join nd_experiment using(nd_experiment_id)   where cvterm.name='plot' and nd_geolocation_id=?"; # and sp_person_id=?";
	my $sh = $self->schema()->storage()->dbh->prepare($plot_count);
	$sh->execute($row->nd_geolocation_id); #, $c->user->get_object->get_sp_person_id);

	my ($count) = $sh->fetchrow_array();

	#if ($count > 0) {

		push @locations,  [ $row->nd_geolocation_id,
				    $row->description,
				    $row->latitude,
				    $row->longitude,
				    $row->altitude,
				    $count, # number of experiments TBD

		];
    }
    return \@locations;

}

sub get_all_years {
    my $self = shift;
    my $year_cv_id = $self->get_project_year_cvterm_id();
    my $rs = $self->schema()->resultset("Project::Projectprop")->search( { type_id=>$year_cv_id }, { distinct => 1, +select => 'value', order_by => { -desc => 'value' }} );
    my @years;

    foreach my $y ($rs->all()) {
	push @years, $y->value();
    }
    return @years;


}

sub get_accessions_by_breeding_program {


}

sub new_breeding_program {
    my $self= shift;
    my $name = shift;
    my $description = shift;

    my $type_id = $self->get_breeding_program_cvterm_id();

    my $rs = $self->schema()->resultset("Project::Project")->search(
	{
	    name => $name,
	});
    if ($rs->count() > 0) {
	return "A breeding program with name '$name' already exists.";
    }

    eval {

		my $role = CXGN::People::Roles->new({bcs_schema=>$self->schema});
		my $error = $role->add_sp_role($name);
		if ($error){
			die $error;
		}

	my $row = $self->schema()->resultset("Project::Project")->create(
	    {
		name => $name,
		description => $description,
	    });

	$row->insert();

	my $prop_row = $self->schema()->resultset("Project::Projectprop")->create(
	    {
		type_id => $type_id,
		project_id => $row->project_id(),

	    });
	$prop_row->insert();

    };
    if ($@) {
	return "An error occurred while generating a new breeding program. ($@)";
    }

}

sub delete_breeding_program {
    my $self = shift;
    my $project_id = shift;

    my $type_id = $self->get_breeding_program_cvterm_id();

    # check if this project entry is of type 'breeding program'
    my $prop = $self->schema->resultset("Project::Projectprop")->search({
	type_id => $type_id,
	project_id => $project_id,
	});

    if ($prop->count() == 0) {
	return 0; # wrong type, return 0.
    }

    $prop->delete();

    my $rs = $self->schema->resultset("Project::Project")->search({
	project_id => $project_id,
	});

    if ($rs->count() > 0) {
	my $pprs = $self->schema->resultset("Project::ProjectRelationship")->search({
	    object_project_id => $project_id,
	});

	if ($pprs->count()>0) {
	    $pprs->delete();
	}
	$rs->delete();
	return 1;
    }
    return 0;
}

sub get_breeding_program_with_trial {
    my $self = shift;
    my $trial_id = shift;

    my $rs = $self->schema->resultset("Project::ProjectRelationship")->search( { subject_project_id => $trial_id });

    my $breeding_projects = [];
    if (my $row = $rs->next()) {
	my $prs = $self->schema->resultset("Project::Project")->search( { project_id => $row->object_project_id() } );
	while (my $b = $prs->next()) {
	    push @$breeding_projects, [ $b->project_id(), $b->name(), $b->description() ];
	}
    }



    return $breeding_projects;
}

sub get_breeding_program_cvterm_id {
    my $self = shift;

    my $breeding_program_cvterm_rs = $self->schema->resultset('Cv::Cvterm')->search( { name => 'breeding_program' });

    my $row;

    if ($breeding_program_cvterm_rs->count() == 0) {
	$row = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'breeding_program','project_property');

    }
    else {
	$row = $breeding_program_cvterm_rs->first();
    }

    return $row->cvterm_id();
}

sub get_breeding_trial_cvterm_id {
    my $self = shift;

     my $breeding_trial_cvterm = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'breeding_program_trial_relationship',  'project_relationship');

    return $breeding_trial_cvterm->cvterm_id();

}

sub get_cross_cvterm_id {
    my $self = shift;

    my $cross_cvterm = SGN::Model::Cvterm->get_cvterm_row($self->schema, 'cross',  'stock_type');
    return $cross_cvterm->cvterm_id();
}

sub _get_design_trial_cvterm_id {
    my $self = shift;
     my $cvterm = $self->schema->resultset("Cv::Cvterm")
      ->find({
		     name   => 'design',

		    });
    return $cvterm->cvterm_id();
}

sub get_project_year_cvterm_id {
    my $self = shift;
    my $year_cvterm_row = $self->schema->resultset('Cv::Cvterm')->find( { name => 'project year' });
    return $year_cvterm_row->cvterm_id();
}

sub get_gt_protocols {
    my $self = shift;
    my $rs = $self->schema->resultset("NaturalDiversity::NdProtocol")->search( { } );
    #print STDERR "NdProtocol resultset rows:\n";
    my @protocols;
    while (my $row = $rs->next()) {
	#print STDERR "Name: " . $row->name() . "\n";
	#print STDERR "Name: " . $row->nd_protocol_id() . "\n";
	#print STDERR $row;
	push @protocols, [ $row->nd_protocol_id(), $row->name()];
    }
    return \@protocols;
}

1;
