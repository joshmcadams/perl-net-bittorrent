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

__END__

=pod

=head1 NAME

Net::BitTorrent::File::DotTorrent

=head1 DESCRIPTION

Wraps the C<.torrent> file.

=head1 SYNOPSYS

=head1 METHODS

=head2 Public

=head3 new

Returns a new C<Net::BitTorrent::File::DotTorrent> object.  The constructor
accepts one argument:

=head4 file

Path to a valid C<.torrent> file.

=head3 get_torrent_file_name

Returns the name of the C<.torrent> file that was passed to the object
constructor.

=head3 multiple_files_exist

Returns true if multiple files exist in the torrent, false if only one file
exists.

=head3 get_suggested_file_name

Returns the suggested name for the file(s) downloaded from the torrent.  If
multiple files are present, the returned value is meant to be a directory.

=head3 get_standard_piece_length

A torrent is divided into equal-sized pieces.  This is the size of those pieces.
It is possible that the final piece in a torrent will not be this standard size.

=head3 get_total_piece_count

Get the total number of pieces to be downloaded in the torrent.  This includes
all standard pieces and the likely last odd-sized piece.

=head3 get_total_download_size

Returns the total amount of data to be downloaded in bytes.

=head3 get_whole_piece_count

Returns the number of pieces that are the standard size.

=head3 get_final_partial_piece_length

If the final piece is not a standard piece, the size of the final piece in
bytes will be returned.

=head3 final_partial_piece_exists

Returns true if an odd-sized piece ends the torrent, false if not.

=head3 get_tracker

Returns the URL of the tracker that controls this torrent.

=head3 get_files

Returns a reference to an array of files that will be downloaded in the torrent.
Each element in the array is a hash reference with two keys:

=head4 length

Size of the file to be downloaded.

=head4 path

Path of the file to be downloaded.

=head3 get_pieces_array

Returns an array of 20-byte SHA1 hashes, each corresponding to the piece at the
same index.

=head2 Private

=head3 _are_necessary_arguments_present_and_okay

Verify the the constructor was passed a decent argument list.

=head3 _parse_torrent_file

Parse the C<.torrent> file useing C<Net::BitTorrent::File>.

=pod

