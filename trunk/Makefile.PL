use warnings;
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Net::BitTorrent',
    VERSION_FROM => 'lib/Net/BitTorrent.pm',
    ABSTRACT     => 'A Port of BitTorrent to Perl',
    AUTHOR       => 'Josh McAdams <joshua dot mcadams at gmail dot com>',
    PREREQ_PM    => {
        'File::Spec'            => 0,
        'Test::More'            => 0,
        'IO::File'              => 0,
        'Net::BitTorrent::File' => 0,
        'List::Util'            => 0,
    },
);

