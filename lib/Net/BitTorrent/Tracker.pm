package Net::BitTorrent::Tracker;

use warnings;
use strict;
use Carp qw(croak);
use Convert::Bencode qw(bdecode);
use LWP::Simple;
use URI;

=pod

=head2 Parameters

=head3 tracker

This is the URL of the tracker that is managing the specific torrent.  This
should be in the 'http://domain:port/path/to/tracker' format so that an easy
GET request can be made to the tracker.  Lucky for us, this is the way that
the tracker is packaged in the C<.torrent> file, so really this is just a
pass-through field from there.

=head3 info_hash [required]

This is the 20-byte sha1 hash for the torrent that is found in the metainfo,
a.k.a. C<.torrent> file.

=head3 peer_id [required]

This is a 20-byte ID that is generated by the local torrent program that is
used to identify the peer.

=head3 port [required]

Port that this peer is listening on for connections from other peers.

=head3 ip

IP address or DNS name for the local peer.

=head3 uploaded

Total amount of data uploaded so far.  This is intended to be representative
of the current downloading session and is meant to be reset when a torrent
is resumed.

=head3 downloaded

Total amount of data downloaded so far.  This is intended to be representative
of the current downloading session and is meant to be reset when a torrent
is resumed.

=head3 left

How much of the torrent file is left to be downloaded?

=head3 event

A keyword sent to the tracker to signfy status:

=head4 started

Sent when the downlaod first begins (or resumes).

=head4 completed (unimplemented)

Sent when downloading is complete.

=head4 stopped (unimplemented)

Sent when leaving the torrent.

=head4 empty

Default when no C<left> argument is present.  This signifies a keep-alive.

=cut

sub new {
    my ( $class, %self ) = @_;

    for (qw(tracker info_hash peer_id port)) {
        croak("$_ required") unless exists $self{$_};
    }

    $self{event} = 'started' unless exists $self{event};

    bless \%self, $class;

    return \%self;
}

sub get_more_peers {
    my ($self) = @_;

    my $uri = URI->new( $self->{tracker} );
    $uri->query_form(
        {
            info_hash => $self->{info_hash},
            peer_id   => $self->{peer_id},
            port      => $self->{port},
            event     => $self->{event},
        }
    );

    $self->{event} = 'empty';

    my $content = get( $uri->as_string() );

    return unless $content;

    my $response = bdecode($content);

    return $response->{'failure reason'}
      if exists $response->{'failure reason'};

    return $response->{peers} || '';
}

1;
