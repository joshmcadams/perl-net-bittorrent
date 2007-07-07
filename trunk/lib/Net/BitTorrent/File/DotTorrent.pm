package Net::BitTorrent::File::DotTorrent;

use warnings;
use strict;
use Carp;
use Net::BitTorrent::File;
use List::Util qw(sum);
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;

    $self->_are_necessary_arguments_present_and_okay()->_parse_torrent_file();

    return $self;
}

sub _are_necessary_arguments_present_and_okay {
    my ($self) = @_;

    croak('A file must be passed to a DotTorrent object')
      unless defined $self->{file};

    croak( $self->{file} . ' does not exist' )
      unless -e $self->{file};

    return $self;
}

sub _parse_torrent_file {
    my ($self) = @_;

    my $nbtf_obj = Net::BitTorrent::File->new( $self->{file} );
    carp('errors initializing Net::BitTorrent::File object')
      unless $nbtf_obj
      and $nbtf_obj->isa('Net::BitTorrent::File');

    $self->{suggested_file_name} = $nbtf_obj->name || '';
    $self->{standard_piece_length} = $nbtf_obj->piece_length
      || $nbtf_obj->info()->{'piece length'}
      || 0;
    $self->{total_piece_count}   = scalar @{ $nbtf_obj->pieces_array() };
    $self->{total_download_size} = $nbtf_obj->length()
      || sum( map { $_->{length} } @{ $nbtf_obj->files() } )
      || 0;
    $self->{whole_piece_count} =
      int( $self->{total_download_size} / $self->{standard_piece_length} ) || 0;
    $self->{final_partial_piece_length} =
      $self->{total_download_size} % $self->{standard_piece_length};
    $self->{files} = defined $nbtf_obj->files()
      ? [
        map {
            {
                path => File::Spec->join(
                    $self->get_suggested_file_name,
                    @{ $_->{path} }
                ),
                length => $_->{length}
            }
          } @{ $nbtf_obj->files() }
      ]
      : [
        {
            path   => $self->get_suggested_file_name,
            length => $self->get_total_download_size
        }
      ];
    $self->{tracker}      = $nbtf_obj->announce() || '';
    $self->{pieces_array} = $nbtf_obj->pieces_array();

    return $self;
}

sub get_torrent_file_name {
    return $_[0]->{file} || '';
}

sub multiple_files_exist {
    return scalar @{ $_[0]->{files} } > 1 ? 1 : 0;
}

sub get_suggested_file_name {
    return $_[0]->{suggested_file_name};
}

sub get_standard_piece_length {
    return $_[0]->{standard_piece_length};
}

sub get_total_piece_count {
    return $_[0]->{total_piece_count};
}

sub get_total_download_size {
    return $_[0]->{total_download_size};
}

sub get_whole_piece_count {
    return $_[0]->{whole_piece_count};
}

sub get_final_partial_piece_length {
    return $_[0]->{final_partial_piece_length};
}

sub final_partial_piece_exists {
    return $_[0]->get_final_partial_piece_length ? 1 : 0;
}

sub get_tracker {
    return $_[0]->{tracker};
}

sub get_files {
    return $_[0]->{files};
}

sub get_pieces_array {
    return $_[0]->{pieces_array};
}

1;

