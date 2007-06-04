package Net::BitTorrent::File::Downloaded;

use warnings;
use strict;
use Carp;
use IO::File;
use List::MoreUtils qw(first_index);
use File::Slurp qw(read_file);
use Digest::SHA1 qw(sha1);

sub new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;

    $self->_check_arguments();

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

    if ( -s $self->{files}->[0]->{path} . '.' . $piece ) {
        return [ { offset => 9, size => 1 } ];
    }

    return [ { offset => 0, size => 10 } ];
}

sub write_block {
    my ( $self, %args ) = @_;

    my $piece_index =
      first_index { $_ == $args{piece} } @{ $self->{remaining_pieces} };
    return unless $piece_index >= 0;

    my $piece_file = $self->{files}->[0]->{path} . '.' . $piece_index;

    my $fh = IO::File->new( $piece_file, 'a' ) || croak($!);
    binmode $fh;
    $fh->seek( $args{offset}, 0 );
    print {$fh} ${ $args{data_ref} } || croak($!);
    $fh->close();

    if (
        ( -s $piece_file == $self->{files}->[0]->{length} )
        && ( $self->{pieces_sha1_hashes}->[$piece_index] eq
            sha1( read_file( $piece_file, binmode => ':raw' ) ) )
        && $self->{remaining_pieces}->[$piece_index] == $args{piece}
      )
    {
        push @{ $self->{completed_pieces} },
          splice @{ $self->{remaining_pieces} }, $piece_index, 1;

        $self->_are_we_done_yet();
    }

    return 1;
}

sub _are_we_done_yet {
    my ($self) = @_;

    return if @{ $self->{remaining_pieces} };

    my $final_file = $self->{files}->[0]->{path};

    my $fh = IO::File->new( $final_file, 'w' ) || croak $!;
    binmode($fh);

    for my $piece ( sort { $a <=> $b } @{ $self->{completed_pieces} } ) {
        my $piece_file = $self->{files}->[0]->{path} . '.' . $piece;
        print {$fh} read_file( $piece_file, binmode => ':raw' ) || croak $!;
        unlink $piece_file;
    }

    $fh->close();
}

1;

