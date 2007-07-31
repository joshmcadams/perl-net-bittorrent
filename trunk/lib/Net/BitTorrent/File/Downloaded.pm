package Net::BitTorrent::File::Downloaded;

use warnings;
use strict;
use Carp;
use IO::File;
use List::MoreUtils qw(first_index);
use File::Slurp qw(read_file);
use Digest::SHA1 qw(sha1);
use File::Spec;

sub new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;

    $self->_check_arguments()->_pick_up_where_we_left_off();

    return $self;
}

sub _check_arguments {
    my ($self) = @_;

    croak('A DotTorrent object is required')
      unless $self->{dt_obj};

    $self->{files}            = $self->{dt_obj}->get_files();
    $self->{remaining_pieces} =
      [ 0 .. $self->{dt_obj}->get_total_piece_count() - 1 ];
    $self->{completed_pieces}      = [];
    $self->{pieces_sha1_hashes}    = $self->{dt_obj}->get_pieces_array();
    $self->{standard_piece_length} =
      $self->{dt_obj}->get_standard_piece_length();
    $self->{final_partial_piece_length} =
      $self->{dt_obj}->get_final_partial_piece_length();
    $self->{total_piece_count} = $self->{dt_obj}->get_total_piece_count();

    return $self;
}

sub _pick_up_where_we_left_off {
    my ($self) = @_;

    for my $piece_file ( glob('*.piece') ) {
        my ($piece_number) = $piece_file;
        $piece_number =~ s/\D//g;

        if ( $self->{pieces_sha1_hashes}->[$piece_number] eq
            sha1( read_file( $piece_file, binmode => ':raw' ) ) )
        {
            my $index_in_remaining =
              first_index { $_ == $piece_number }
              @{ $self->{remaining_pieces} };
            push @{ $self->{completed_pieces} },
              splice @{ $self->{remaining_pieces} }, $index_in_remaining, 1;
            $self->_are_we_done_yet($piece_number);
        }
        else {
            unlink $piece_file;
        }
    }

    return $self;
}

sub get_remaining_piece_list {
    return $_[0]->{remaining_pieces};
}

sub get_completed_piece_list {
    return $_[0]->{completed_pieces};
}

sub get_remaining_blocks_list_for_piece {
    my ( $self, $piece ) = @_;

    if ( ( first_index { $piece == $_ } @{ $self->{completed_pieces} } ) >= 0 )
    {
        return [];
    }

    my $piece_length =
      ( $self->{final_partial_piece_length}
          && ( $piece == ( $self->{total_piece_count} - 1 ) ) )
      ? $self->{final_partial_piece_length}
      : $self->{standard_piece_length};

    if ( my $size = -s $piece . '.piece' ) {
        return [ { offset => $size, size => $piece_length - $size } ];
    }

    return [ { offset => 0, size => $piece_length } ];
}

sub write_block {
    my ( $self, %args ) = @_;

    my $piece_index =
      first_index { $_ == $args{piece} } @{ $self->{remaining_pieces} };
    return unless $piece_index >= 0;

    my $piece_file = $args{piece} . '.piece';

    # write the data to a 'piece' file
    {
        my $fh = IO::File->new( $piece_file, 'a' ) || croak($!);
        binmode $fh;
        $fh->seek( $args{offset}, 0 );
        print {$fh} ${ $args{data_ref} } || croak($!);
        $fh->close();
    }

    my $completed_piece_length =
        $piece_index == $self->{total_piece_count} - 1
      ? $self->{final_partial_piece_length}
      : $self->{standard_piece_length};

    if (
        ( -s $piece_file == $completed_piece_length )
        && ( $self->{pieces_sha1_hashes}->[ $args{piece} ] eq
            sha1( read_file( $piece_file, binmode => ':raw' ) ) )
      )
    {
        push @{ $self->{completed_pieces} },
          splice @{ $self->{remaining_pieces} }, $piece_index, 1;

        $self->_are_we_done_yet($piece_index);
    }

    return 1;
}

sub _build_out_directories {
    my ($file_name) = @_;

    my @dirs = File::Spec->splitdir($file_name);
    pop @dirs;
    my $long_dir;
    for my $dir (@dirs) {
        $long_dir =
          defined $long_dir ? File::Spec->join( $long_dir, $dir ) : $dir;
        if ( !-d $long_dir ) {
            mkdir $long_dir or die $!;
        }
    }

    return 1;
}

sub _write_pieces_to_file {
    my ( $file, $pieces ) = @_;

    my $current_size = 0;
    my $target_size  = $file->{length};

    my $fh = IO::File->new( $file->{path}, O_RDWR | O_CREAT ) || croak $!;
    binmode($fh);

    my $counter = 1;
    while ( $current_size < $target_size ) {
        my $piece             = shift @{$pieces};
        my $piece_file        = $piece->{piece} . '.piece';
        my $needed_byte_count = $target_size - $current_size;

        if ( $piece->{size} <= $needed_byte_count ) {
            print {$fh} read_file( $piece_file, binmode => ':raw' ) || croak $!;
            unlink $piece_file;
            $current_size += $piece->{size};
        }
        else {
            my $data = read_file( $piece_file, binmode => ':raw' );
            print {$fh} substr( $data, 0, $needed_byte_count )
              || croak $!;
            my $fh = IO::File->new( $piece_file, 'w' ) or die $!;
            binmode $fh;
            print {$fh} substr( $data, $needed_byte_count );
            $fh->close();
            $current_size += $needed_byte_count;
            $piece->{size} = -s $piece_file;
            unshift @{$pieces}, $piece if $current_size;
        }

        last if $current_size >= $target_size;
    }

    $fh->close();

    return 1;
}

sub _are_we_done_yet {
    my ( $self, $piece_index ) = @_;

    return if @{ $self->{remaining_pieces} };

    my @pieces = map { { piece => $_, size => -s $_ . '.piece' } }
      sort { $a <=> $b } @{ $self->{completed_pieces} };

    for my $file ( @{ $self->{files} } ) {
        _build_out_directories( $file->{path} );
        _write_pieces_to_file( $file, \@pieces );
    }
}

1;

__END__

=pod

=head1 NAME

Net::BitTorrent::File::Download

=head1 DESCRIPTION

Object that wraps the file physically found on the local disk.

=head1 SYNOPSYS

=head1 METHODS

=head2 Public

=head3 new

Returns a new C<Net::BitTorrent::File::Download> object.  The constructor
accepts one argument:

=head4 dt_obj

A reference to a C<Net::BitTorrent::File::DotTorrent> object.

=head3 get_remaining_piece_list

Returns a reference to an array of indexes that have not been fully downloaded.

=head3 get_completed_piece_list

Returns a reference to an array of indexes that have been fully downloaded.

=head3 get_remaining_blocks_list_for_piece

Returns a reference to an array of hashes that represent blocks that still
need to be downloaded within a piece.  The keys in the hashes are:

=head4 offset

Block offset within piece.

=head4 size

Block size within piece.

=head3 write_block

Writes data to the downloaded file(s).  The method accepts three arguments:

=head4 piece

Zero-based index of the piece that is being written to.

=head4 offset

Block-offset for the data that is being written to within the piece.

=head4 data_ref

Scalar reference to the data that will be written.

=head2 Private

=head3 _check_arguments

Make sure that the constructor was passed reasonable arguments.

=head3 _pick_up_where_we_left_off

If we are resuming a download, determine how far along we were.

=head3 _build_out_directories

If this is a multi-file torrent, build out the directory structure that we'll
need to write the data files to.

=head3 _write_pieces_to_file

After we have downloaded all of the pieces to individual piece files, we need
to put them together into the final files.

=head3 _are_we_done_yet

See if we are finished.

=cut

