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
    changed => 'Mon Dec 28 23:19:25 CET 2015',
);

Irssi::settings_add_str('ttirssi', 'ttirssi_url', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_username', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_password', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_win', 'ttirssi');

our $ttrss_url;
our $ttrss_api;
our $ttrss_username;
our $ttrss_password;
our $ttrss_session;
our $ttrss_last_id;
our $win_name;
our $win;

sub print_info {
    my ($message, $type) = @_;

    if(not defined $type) {
        Irssi::print("%g[ttirssi]%n " . $message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        Irssi::print("%g[ttirssi] %RError: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'info') {
        Irssi::print("%g[ttirssi] %GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } else {
        Irssi::print("%g[ttirssi]%n " . $message, MSGLEVEL_CLIENTCRAP);
    }
}

sub print_win {
    my ($message, $type) = @_;

    if(not defined $type) {
        $win->print($message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        $win->print("%RError: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'info') {
        $win->print("%GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } else {
        $win->print($message, MSGLEVEL_CLIENTCRAP);
    }
}

sub ttrss_login {
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
        &print_win("(" . $response->code . ") " . $response->message, "error");
        return 0;
    }
}

sub ttrss_parse_feed {
    my ($feed, $limit) = @_;
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $first_item = (($ttrss_last_id eq -1) ? "" : '"since_id" : $ttrss_last_id,');
    my $post_data = '{ "sid":"' . $ttrss_session . '", "op":"getHeadlines", "feed_id": ' . 
                    $feed . ', ' . $first_item . '"order_by":"date_reverse", "limit":' . $limit . ' }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp = JSON->new->utf8->decode($response->content);
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            my @headlines = @{$json_resp->{'content'}};
            foreach my $feed (@headlines) {
                $win->print("[%B" . $feed->{'feed_title'} . "%n] " . $feed->{'title'} . " %r" .
                            $feed->{'link'} . "%n", MSGLEVEL_PUBLIC);
                $ttrss_last_id = $feed->{'id'};
            }
        } else {
            &print_win("Couldn't fetch feed headlines (unknown error)", "error");
        }
    } else {
        &print_win("Couldn't fetch feed headlines: (" . $response->code . ") " . $response->message, "error");
    }
}

sub create_win {
    # If desired window already exists, don't create a new one
    $win = Irssi::window_find_name($win_name);
    if($win) {
        &print_info("Will use an existing window '$win_name'", "info");
        return 1;
    }

    $win = Irssi::Windowitem::window_create($win_name, 1);
    if(not $win) {
        &print_info("Failed to create window '$win_name'", "error");
        return 0;
    }

    &print_info("Created a new window '$win_name'", "info");
    $win->set_name($win_name);
    return 1;
}

# Get settings
# TODO: Check
$ttrss_url = Irssi::settings_get_str('ttirssi_url');
$ttrss_username = Irssi::settings_get_str('ttirssi_username');
$ttrss_password = Irssi::settings_get_str('ttirssi_password');
$win_name = Irssi::settings_get_str('ttirssi_win');
$ttrss_api = "$ttrss_url/api/";
$ttrss_last_id = -1;

if(!&create_win()) {
    return;
}

# Try to login
if(&ttrss_login()) {
    &print_info("Session ID: $ttrss_session", "info");
    &ttrss_parse_feed(-3, 5);
} else {
    &print_info("Couldn't get session ID");
}
