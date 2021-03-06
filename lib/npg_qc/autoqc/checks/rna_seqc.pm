package npg_qc::autoqc::checks::rna_seqc;

use Moose;
use namespace::autoclean;
use English qw( -no_match_vars );
use Carp;
use Readonly;
use DateTime;
use IO::File;
use npg_tracking::util::types;
use File::Spec;
use File::Path qw( make_path );

extends qw(npg_qc::autoqc::checks::check);

with qw(npg_tracking::data::reference::find 
        npg_common::roles::software_location
        npg_tracking::data::transcriptome::find
       );

our $VERSION = '0';

Readonly::Scalar our $EXT => q[bam];

Readonly::Scalar my $RNASEQC_JAR_NAME  => q[RNA-SeQC.jar];
Readonly::Scalar my $CHILD_ERROR_SHIFT => 8;
Readonly::Scalar my $MAX_READS         => 100;
Readonly::Scalar my $PAIRED_FLAG       => 0x1;
Readonly::Scalar my $RRNA_ALIGNER      => q[bwa];
Readonly::Scalar my $RRNA_STRAIN       => q[default_rRNA];
Readonly::Scalar my $METRICS_FILE_NAME => q[metrics.tsv];
Readonly::Scalar my $MINUS_ONE         => -1;

Readonly::Hash   my %RNASEQC_METRICS_FIELDS_MAPPING => {
    '3\' Norm'                              => 'end_3_norm',
    '5\' Norm'                              => 'end_5_norm',
    'End 1 % Sense'                         => 'end_1_pct_sense',
    'End 1 Antisense'                       => 'end_1_antisense',
    'End 1 Sense'                           => 'end_1_sense',
    'End 2 % Sense'                         => 'end_2_pct_sense',
    'End 2 Antisense'                       => 'end_2_antisense',
    'End 2 Sense'                           => 'end_2_sense',
    'Exonic Rate'                           => 'exonic_rate',
    'Expression Profiling Efficiency'       => 'expression_profiling_efficiency',
    'Genes Detected'                        => 'genes_detected',
    'Mean CV'                               => 'mean_cv',
    'Mean Per Base Cov.'                    => 'mean_per_base_cov',
    'rRNA'                                  => 'rrna',
    'rRNA rate'                             => 'rrna_rate',
};

has '+file_type' => (default => $EXT,);

has '+aligner' => (default => 'fasta',
                   is => 'ro',
                   writer => '_set_aligner',);

has 'output_dir' => (is       => 'ro',
                     isa      => 'Str',
                     required => 0,
                     lazy     => 1,
                     builder  => '_build_output_dir',);

sub _build_output_dir {
    my ($self) = @_;
    my $qc_out_path = $self->qc_out;
    my $output_dir = File::Spec->catdir($qc_out_path, $self->result->filename_root . q[_rna_seqc]);
    return $output_dir;
}

has '_java_jar_path' => (is       => 'ro',
                         isa      => 'NpgCommonResolvedPathJarFile',
                         coerce   => 1,
                         default  => $RNASEQC_JAR_NAME,
                         init_arg => undef,);

has '_ttype_gtf_column' => (is      => 'ro',
                            isa     => 'Int',
                            default => 2,);

has '_alignments_in_bam' => (is      => 'ro',
                             isa     => 'Bool',
                             lazy    => 1,
                             builder => '_build_alignments_in_bam',);

sub _build_alignments_in_bam {
    my $self = shift;
    my $aligned = 0;
    my $command = $self->samtools_cmd . ' view -H ' . $self->_bam_file . ' |';
    my $ph = IO::File->new($command) or croak qq[Cannot fork '$command', error $ERRNO];
    while (my $line = <$ph>) {
        if (!$aligned && $line =~ /^\@SQ/smx) {
            $aligned = 1;
        }
    }
    $ph->close();
    return $aligned;
}

has '_is_paired_end' => (is      => 'ro',
                         isa     => 'Bool',
                         lazy    => 1,
                         builder => '_build_is_paired_end',);

sub _build_is_paired_end {
    my ($self) = @_;
    my $paired = 0;
    my $flag;
    my $num_reads = 0;
    my $view_command = $self->samtools_cmd. q[ view ]. $self->_bam_file. q[ 2>/dev/null | ];
    my $ph = IO::File->new($view_command) or croak "Error viewing bam: $OS_ERROR\n";
    while (my $line = <$ph>) {
        next if $line =~ /^\@/ismx;
        my @read = split /\t/smx, $line;
        $flag = $read[1];
        if ($flag & $PAIRED_FLAG){
            $paired = 1;
        }
        $num_reads += 1;
        # if enough reads have been read and none is PAIRED
        # assume it isn't and stop reading file
        last if ($num_reads >= $MAX_READS || $paired);
    }
    $ph->close();
    return $paired;
}

has '_is_rna_alignment' => (is      => 'ro',
                            isa     => 'Bool',
                            lazy    => 1,
                            builder => '_build_is_rna_alignment',);

sub _build_is_rna_alignment {
    my ($self) = @_;
    my $rna_alignment = 0;
    my $command = $self->samtools_cmd . ' view -H ' . $self->_bam_file . ' |';
    my $ph = IO::File->new($command) or croak qq[Cannot fork '$command', error $ERRNO];
    while (my $line = <$ph>) {
        if (!$rna_alignment && $line =~ /^\@PG\s+.*tophat/ismx) {
            $rna_alignment = 1;
        }
    }
    $ph->close();
    return $rna_alignment;

}

has '_input_str' => (is       => 'ro',
                     isa      => 'Str',
                     lazy     => 1,
                     builder  => '_build_input_str',
                     init_arg => undef,);

sub _build_input_str {
    my ($self) = @_;
    my $sample_id = $self->lims->sample_id;
    my $library_name = $self->lims->library_name // $sample_id;
    my @library_names = split q[ ], $library_name;
    my $input_file = $self->_bam_file;
    return qq["$library_names[0]|$input_file|$sample_id"];
}

has '_ref_genome' => (is       => 'ro',
                      isa      => 'Str',
                      required => 0,
                      lazy     => 1,
                      builder  => '_build_ref_genome',);

sub _build_ref_genome {
    my ($self) = @_;
    my $reference_fasta = $self->refs->[0] // q[];
    return $reference_fasta;
}

has '_bam_file' => (is      => 'ro',
                    isa     => 'NpgTrackingReadableFile',
                    lazy    => 1,
                    builder => '_build_bam_file',);

sub _build_bam_file {
    my $self = shift;
    return $self->input_files->[0];
}

has '_annotation_gtf' => (is       => 'ro',
                          isa      => 'Str',
                          required => 0,
                          lazy     => 1,
                          builder  => '_build_annotation_gtf',);

sub _build_annotation_gtf {
    my $self = shift;
    my $trans_gtf = $self->rnaseqc_gtf_file // q[];
    return $trans_gtf;
}

has '_ref_rrna' => (is       => 'ro',
                    isa      => 'Str',
                    required => 0,
                    lazy     => 1,
                    builder  => '_build_ref_rrna',);

sub _build_ref_rrna {
    my $self = shift;
    my ($organism, $strain, $transcriptome) = $self->parse_reference_genome($self->lims->reference_genome);
    $self->_set_aligner($RRNA_ALIGNER);
    $self->_set_strain($RRNA_STRAIN);
    $self->_set_species($organism);
    my $ref_rrna = $self->refs->[0] // q[];
    return $ref_rrna;
}

sub _command {
    my ($self) = @_;
    my $ref_rrna_option = q[];
    my $single_end_option = q[];
    if(!$self->_is_paired_end){
        $single_end_option = q[-singleEnd];
    }
    if($self->_ref_rrna){
        $ref_rrna_option = q[-BWArRNA ]. $self->_ref_rrna;
    }
    my $command = $self->java_cmd. sprintf q[ -Xmx4000m -XX:+UseSerialGC -XX:-UsePerfData -jar %s -s %s -o %s -r %s -t %s -ttype %d %s %s],
                                           $self->_java_jar_path,
                                           $self->_input_str,
                                           $self->output_dir,
                                           $self->_ref_genome,
                                           $self->_annotation_gtf,
                                           $self->_ttype_gtf_column,
                                           $single_end_option,
                                           $ref_rrna_option;
    return $command;
}

override 'can_run' => sub {
    my $self = shift;
    if (! $self->_annotation_gtf) {
        $self->result->add_comment(q[No GTF annotation available]);
        return 0;
    }
    return 1;
};

override 'execute' => sub {
    my ($self) = @_;
    my @comments;
    my $can_execute = 1;
    if (super() == 0) {
    	return 1;
    }
    $self->result->set_info('Jar', qq[RNA-SeqQC $RNASEQC_JAR_NAME]);
    if (! $self->_ref_genome) {
        push @comments, q[No reference genome available];
        $can_execute = 0;
    }
    if(! $self->_alignments_in_bam) {
        push @comments, q[BAM file is not aligned];
        $can_execute = 0;
    }
    if (! $self->_is_rna_alignment) {
        push @comments, q[BAM file is not RNA alignment];
        $can_execute = 0;
    }
    if (! $can_execute || ! $self->can_run()) {
        my $can_run_message = join q[; ], @comments;
        $self->result->add_comment($can_run_message);
        return 1;
    }
    my $command = $self->_command();
    carp qq[EXECUTING $command time ]. DateTime->now();
    if (system $command) {
        my $error = $CHILD_ERROR >> $CHILD_ERROR_SHIFT;
        croak sprintf "Child %s exited with value %d\n", $command, $error;
    } else {
        my $results = $self->_parse_metrics();
        $self->_save_results($results);
    };
    return 1;
};

sub _parse_metrics {
    my ($self) = @_;
    my $filename = File::Spec->catfile($self->output_dir, $METRICS_FILE_NAME);
    if (! -e $filename) {
        croak qq[No such file $filename: cannot parse RNA-SeQC metrics];
    }
    my $fh = IO::File->new($filename, 'r');
    my @lines;
    if (defined $fh){
        @lines = $fh->getlines();
    }
    $fh->close();
    my @keys = split /\t/smx, $lines[0];
    my @values = split /\t/smx, $lines[1], $MINUS_ONE;
    if (scalar @keys != scalar @values) {
        croak q[Mismatch in number of keys and values];
    }
    my $i = 0;
    my $results = {};
    foreach my $key (@keys){
        chomp $values[$i];
        chomp $key;
        $results->{$key} = $values[$i];
        $i++;
    }
    return $results;
};

sub _save_results {
    my ($self, $results) = @_;
    foreach my $key (keys %RNASEQC_METRICS_FIELDS_MAPPING) {
        my $value = $results->{$key};
        if (defined $value) {
            my $attr_name = $RNASEQC_METRICS_FIELDS_MAPPING{$key};
            if ($value eq q[NaN]) {
                carp qq[Value of $attr_name is 'NaN', skipping...];
            } else {
                $self->result->$attr_name($value);
            }
        }
        delete $results->{$key};
    }
    $self->result->other_metrics($results);
    $self->result->output_dir($self->output_dir);
    return;
}
__PACKAGE__->meta->make_immutable();

1;

__END__


=head1 NAME

npg_qc::autoqc::checks::rna_seqc 

=head1 SYNOPSIS

=head1 DESCRIPTION

QC check that runs Broad Institute's RNA-SeQC; a java program which computes a
series of quality control metrics for RNA-seq data. The output consists of
HTML reports and tab delimited files of metrics data from which a selection of
them are extracted to generate an autoqc result. The output directory is
created by default using the sample's filename root.

=head1 SUBROUTINES/METHODS

=head2 new

    Moose-based.

=head1 DIAGNOSTICS

    None.

=head1 CONFIGURATION AND ENVIRONMENT

=head1 INCOMPATIBILITIES

    None known.

=head1 BUGS AND LIMITATIONS

=head1 DEPENDENCIES

=over

=item Moose

=item namespace::autoclean

=item English

=item Carp

=item Readonly

=item DateTime

=item IO::File

=item npg_qc::autoqc::checks::check

=item npg_tracking::data::reference::find

=item npg_common::roles::software_location

=item npg_tracking::data::transcriptome::find

=back

=head1 AUTHOR

Ruben E Bautista-Garcia<lt>rb11@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2016 Genome Research Limited

This file is part of NPG.

NPG is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
