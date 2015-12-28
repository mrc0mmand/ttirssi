use strict;
use warnings;
use Irssi;
use LWP::UserAgent;
use HTTP::Request;
use JSON;
use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors => 'Frantisek Sumsal',
    contact => 'frantisel@sumsal.cz',
    name    => 'ttirssi',
    description => 'TODO',
    license => 'BSD',
    url     => 'https://github.com/mrc0mmand/ttirssi',
    changed	=> 'Mon Dec 28 23:19:25 CET 2015',
);

Irssi::settings_add_str('ttirssi', 'ttirssi_url', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_username', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_password', '');

our $ttrss_url;
our $ttrss_api;
our $ttrss_username;
our $ttrss_password;
our $ttrss_session;

sub ttrss_login() {
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $post_data = '{ "op":"login", "user":"' . $ttrss_username . '","password":"' . $ttrss_password . '"}';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp = JSON->new->utf8->decode($response->content);
        $ttrss_session = $json_resp->{'content'}->{'session_id'};
        return 1;
    } else {
        print "Error: (" . $response->code . ")" . $response->message;
        return 0;
    }
}

# Get settings
$ttrss_url = Irssi::settings_get_str('ttirssi_url');
$ttrss_api = "$ttrss_url/api/";
$ttrss_username = Irssi::settings_get_str('ttirssi_username');
$ttrss_password = Irssi::settings_get_str('ttirssi_password');

# Try to login
if(ttrss_login()) {
    print "Session ID: $ttrss_session";
} else {
    print "Couldn't get session ID";
}
