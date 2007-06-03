use warnings;
use strict;
use Test::More qw(no_plan);
use Test::MockObject;
use String::Random;
use File::Slurp;

use_ok('Net::BitTorrent::File::Downloaded');

my %mocks = (
    'get_torrent_file_name'          => sub { File::Spec->join('x') },
    'multiple_files_exist'           => sub { 0 },
    'get_suggested_file_name'        => sub { 'ARTISTIC' },
    'get_standard_piece_length'      => sub { 32768 },
    'get_total_piece_count'          => sub { 1 },
    'get_total_download_size'        => sub { 6169 },
    'get_whole_piece_count'          => sub { 0 },
    'final_partial_piece_exists'     => sub { 1 },
    'get_final_partial_piece_length' => sub { 6169 },
    'get_tracker' => sub { 'http://my.tracker:6969/announce' },
    'get_files'   => sub { [ { 'length' => '6169', 'path' => 'ARTISTIC', }, ] },
    'get_pieces_array' => sub { ['x'] },
);

my $dt_obj = Test::MockObject->new();
$dt_obj->mock( $_, $mocks{$_} ) for keys %mocks;

my $d = Net::BitTorrent::File::Downloaded->new( dt_obj => $dt_obj );
isa_ok( $d, 'Net::BitTorrent::File::Downloaded' );

is_deeply(
    $d->get_remaining_piece_list,
    [ 0 .. $dt_obj->get_total_piece_count() - 1 ],
    'remaining piece list'
);
is_deeply( $d->get_completed_piece_list, [], 'completed piece list' );
is_deeply(
    $d->get_remaining_segments_list_for_piece(0),
    [ { offset => 0, size => $dt_obj->get_total_download_size } ],
    'remaining segments for first piece'
);

my $data = String::Random->new()->randpattern( '.' x 6169 );

ok(
    $d->write_segment(
        piece    => 0,
        offset   => 0,
        size     => 6169,
        data_ref => \$data
    ),
    'write a segment'
);

my $data_from_file = read_file( $dt_obj->get_suggested_file_name() );
is( $data_from_file, $data, 'everything wrote appropriately' );

is_deeply( $d->get_remaining_piece_list, [], 'remaining piece list' );
is_deeply( $d->get_completed_piece_list, [0], 'completed piece list' );

