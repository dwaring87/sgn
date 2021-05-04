#!/usr/bin/env perl


=head1 NAME

CreateMaterializedMarkerview.pm

=head1 SYNOPSIS

mx-run CreateMaterializedMarkerview [options] -H hostname -D dbname -u username [-F]

this is a subclass of L<CXGN::Metadata::Dbpatch>
see the perldoc of parent class for more details.

=head1 DESCRIPTION

This patch adds a public.create_materialized_markerview(boolean) function which can be used to build 
and refresh the unified marker materialized view.  The function uses all of the reference genomes / species 
from the currently stored genotype data in the nd_protocolprop table to build the query for the marker 
materialized view.  If new genotype data is added, this function should be used to rebuild the marker 
materialized view rather than simply refreshing it in case there are new references or species in the data.

=head1 AUTHOR

David Waring <djw64@cornell.edu>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


package CreateMaterializedMarkerview;

use Moose;
use Bio::Chado::Schema;
use Try::Tiny;
extends 'CXGN::Metadata::Dbpatch';


has '+description' => ( default => <<'' );
This patch adds the create_materialized_markerview function to build and populate the materialized_markerview mat view

has '+prereq' => (
	default => sub {
        [],
    },

);

sub patch {
    my $self=shift;

    print STDOUT "Executing the patch:\n " .   $self->name . ".\n\nDescription:\n  ".  $self->description . ".\n\nExecuted by:\n " .  $self->username . " .";

    print STDOUT "\nChecking if this db_patch was executed before or if previous db_patches have been executed.\n";

    print STDOUT "\nExecuting the SQL commands.\n";
    
    $self->dbh->do(<<EOSQL);

-- Create the function to build the materialized markerview
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE OR REPLACE FUNCTION public.create_materialized_markerview(refresh boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS \$function\$
	DECLARE
		maprow RECORD;
		querystr TEXT;
		queries TEXT[];
		matviewquery TEXT;
	BEGIN
		DROP MATERIALIZED VIEW IF EXISTS public.materialized_markerview;
		FOR maprow IN (
			SELECT value->>'species_name' AS species,
				concat(
					substring(split_part(value->>'species_name', ' ', 1), 1, 1),
					substring(split_part(value->>'species_name', ' ', 2), 1, 1)
				) AS species_abbreviation,
				value->>'reference_genome_name' AS reference_genome,
				replace(replace(value->>'reference_genome_name', '_', ''), ' ', '') AS reference_genome_cleaned
			FROM nd_protocolprop 
			WHERE type_id = (SELECT cvterm_id FROM public.cvterm WHERE name = 'vcf_map_details')
			GROUP BY species, reference_genome
		)
		LOOP
			querystr := 'SELECT nd_protocolprop.nd_protocol_id, ''' || maprow.species || ''' AS species_name, ''' || maprow.reference_genome || ''' AS reference_genome_name, s.value->>''name'' AS marker_name, s.value->>''chrom'' AS chrom, (s.value->>''pos'')::int AS pos, s.value->>''ref'' AS ref, s.value->>''alt'' AS alt, concat(''' || maprow.species_abbreviation || ''', ''' || maprow.reference_genome_cleaned || ''', ''_'', s.value->>''chrom'', ''_'', s.value->>''pos'') AS variant_name FROM nd_protocolprop, LATERAL jsonb_each(nd_protocolprop.value) s(key, value) WHERE type_id = (SELECT cvterm_id FROM public.cvterm WHERE name = ''vcf_map_details_markers'') AND nd_protocol_id IN (SELECT nd_protocol_id FROM nd_protocolprop WHERE value->>''species_name'' = ''' || maprow.species || ''' AND type_id = (SELECT cvterm_id FROM public.cvterm WHERE name = ''vcf_map_details''))';
			queries := array_append(queries, querystr);
		END LOOP;
		matviewquery := array_to_string(queries, ' UNION ');
		EXECUTE 'CREATE MATERIALIZED VIEW public.materialized_markerview AS (' || matviewquery || ') WITH NO DATA';
		CREATE INDEX materialized_markerview_idx1 ON public.materialized_markerview(nd_protocol_id);
		CREATE INDEX materialized_markerview_idx2 ON public.materialized_markerview(species_name);
		CREATE INDEX materialized_markerview_idx3 ON public.materialized_markerview(reference_genome_name);
		CREATE INDEX materialized_markerview_idx4 ON public.materialized_markerview(marker_name);
		CREATE INDEX materialized_markerview_idx5 ON public.materialized_markerview(UPPER(marker_name));
		CREATE INDEX materialized_markerview_idx6 ON public.materialized_markerview(chrom);
		CREATE INDEX materialized_markerview_idx7 ON public.materialized_markerview(pos);
		CREATE INDEX materialized_markerview_idx8 ON public.materialized_markerview(variant_name);
		CREATE INDEX materialized_markerview_idx9 ON public.materialized_markerview(UPPER(variant_name));
		CREATE INDEX materialized_markerview_idx10 ON public.materialized_markerview USING GIN(marker_name gin_trgm_ops);
		CREATE INDEX materialized_markerview_idx11 ON public.materialized_markerview USING GIN(variant_name gin_trgm_ops);
		IF \$1 THEN
			REFRESH MATERIALIZED VIEW public.materialized_markerview;
		END IF;
		GRANT SELECT ON public.materialized_markerview TO web_usr;
		RETURN \$1;
	END
\$function\$;

-- Build an empty materialized view (will need to be manually refreshed)
SELECT public.create_materialized_markerview(false);

-- Grant access to the web_usr
GRANT SELECT ON public.materialized_markerview TO web_usr;


EOSQL
    
    print "You're done!\n";
}


####
1; #
####
