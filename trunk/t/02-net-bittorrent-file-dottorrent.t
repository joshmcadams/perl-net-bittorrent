use warnings;
use strict;
use Test::More tests => 55;
use File::Spec;
use IO::File;

use_ok('Net::BitTorrent::File::DotTorrent');

FILE_REQUIRED: {
    my $dt = eval { Net::BitTorrent::File::DotTorrent->new(); };
    ok( $@, 'file required for construction' );
}

NON_EXISTANT_FILE: {
    my $dt = eval {
        Net::BitTorrent::File::DotTorrent->new(
            file => 'hopefully_this_does_not_exist.xyz', );
    };
    ok( $@, 'file must exist' );
}

my @tests = (
    {
        get_torrent_file_name => File::Spec->join(
            qw(t 02-net-bittorrent-file-dottorrent sample_one.torrent)),
        multiple_files_exist => 0,

    },
);

SEND_A_FILE: {
    my @tests = (
        {
            get_torrent_file_name => File::Spec->join(
                qw(t 02-net-bittorrent-file-dottorrent sample_one.torrent)),
            multiple_files_exist           => 0,
            get_suggested_file_name        => 'ARTISTIC',
            get_standard_piece_length      => 32768,
            get_total_piece_count          => 1,
            get_total_download_size        => 6169,
            get_whole_piece_count          => 0,
            final_partial_piece_exists     => 1,
            get_final_partial_piece_length => 6169,
            get_tracker                    => 'http://my.tracker:6969/announce',
            get_files => [ { 'length' => '6169', 'path' => 'ARTISTIC', }, ],
            get_pieces_array => pick_up_the_pieces(
                File::Spec->join(
                    qw(t 02-net-bittorrent-file-dottorrent sample_one.pieces))
            ),
        },
        {
            get_torrent_file_name => File::Spec->join(
                qw(t 02-net-bittorrent-file-dottorrent sample_two.torrent)),
            multiple_files_exist           => 0,
            get_suggested_file_name        => 'random_crap.txt',
            get_standard_piece_length      => 32768,
            get_total_piece_count          => 2,
            get_total_download_size        => 32770,
            get_whole_piece_count          => 1,
            final_partial_piece_exists     => 1,
            get_final_partial_piece_length => 2,
            get_tracker                    => 'http://my.tracker:6969/announce',
            get_files                      =>
              [ { 'length' => '32770', 'path' => 'random_crap.txt', }, ],
            get_pieces_array => pick_up_the_pieces(
                File::Spec->join(
                    qw(t 02-net-bittorrent-file-dottorrent sample_two.pieces))
            ),
        },
        {
            get_torrent_file_name => File::Spec->join(
                qw(t 02-net-bittorrent-file-dottorrent sample_three.torrent)),
            multiple_files_exist           => 0,
            get_suggested_file_name        => 'random_crap.txt',
            get_standard_piece_length      => 32768,
            get_total_piece_count          => 1,
            get_total_download_size        => 32768,
            get_whole_piece_count          => 1,
            final_partial_piece_exists     => 0,
            get_final_partial_piece_length => 0,
            get_tracker                    => 'http://my.tracker:6969/announce',
            get_files                      =>
              [ { 'length' => '32768', 'path' => 'random_crap.txt', }, ],
            get_pieces_array => pick_up_the_pieces(
                File::Spec->join(
                    qw(t 02-net-bittorrent-file-dottorrent sample_three.pieces))
            ),
        },
        {
            get_torrent_file_name => File::Spec->join(
                qw(t 02-net-bittorrent-file-dottorrent sample_four.torrent)),
            multiple_files_exist           => 1,
            get_suggested_file_name        => 'sample_four',
            get_standard_piece_length      => 32768,
            get_total_piece_count          => 2,
            get_total_download_size        => 32802,
            get_whole_piece_count          => 1,
            final_partial_piece_exists     => 1,
            get_final_partial_piece_length => 34,
            get_tracker => 'http://sometracker:6969/announce',
            get_files   => [
                {
                    'length' => '32770',
                    'path'   =>
                      File::Spec->join(qw(sample_four random_crap_one.txt)),
                },
                {
                    'length' => '32',
                    'path'   =>
                      File::Spec->join(qw(sample_four random_crap_two.txt)),
                },
            ],
            get_pieces_array => pick_up_the_pieces(
                File::Spec->join(
                    qw(t 02-net-bittorrent-file-dottorrent sample_four.pieces))
            ),
        },

    );

    for my $test (@tests) {

        my $dt =
          Net::BitTorrent::File::DotTorrent->new(
            file => $test->{get_torrent_file_name} );
        isa_ok( $dt, 'Net::BitTorrent::File::DotTorrent' );

        for my $method ( keys %{$test} ) {
            if ( ref $test->{$method} ) {
                is_deeply( $dt->$method, $test->{$method}, $method );
            }
            else {
                is( $dt->$method, $test->{$method}, $method );
            }
        }
    }
}

sub pick_up_the_pieces {
    my ($file) = shift;

    my $file_size = -s $file;
    die("size of $file is not a multiple of 20") unless $file_size % 20 == 0;
    my $piece_count = int( $file_size / 20 );

    my @pieces_array;
    my $buffer;

    my $fh = IO::File->new( $file, 'r' ) or die $!;
    binmode $fh;

    for my $piece ( 1 .. $piece_count ) {
        read( $fh, $buffer, 20 ) == 20
          or die('unable to read 20 byte chunk from file');
        push @pieces_array, $buffer;
    }

    $fh->close();
    return \@pieces_array;
}

