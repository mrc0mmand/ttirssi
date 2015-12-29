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
Irssi::settings_add_int('ttirssi', 'ttirssi_update_interval', '60');
Irssi::settings_add_int('ttirssi', 'ttirssi_article_limit', '25');

our $ttrss_url;
our $ttrss_api;
our $ttrss_username;
our $ttrss_password;
our $ttrss_session;
our $ttrss_last_id;
our $ttrss_logged;
our $win_name;
our $win;
our $update_interval;
our $update_event;
our $article_limit;
our $default_feed;

sub print_info {
    my ($message, $type) = @_;

    if(not defined $type) {
        Irssi::print("%g[ttirssi]%n " . $message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        Irssi::print("%g[ttirssi] %RError: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'info') {
        Irssi::print("%g[ttirssi] %GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'warn') {
        Irssi::print("%g[ttirssi] %YWarning: %n" . $message, MSGLEVEL_CLIENTCRAP)
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

sub ttrss_parse_error {
    my $json_resp = shift;

    if(exists $json_resp->{'content'}{'error'}) {
        return $json_resp->{'content'}{'error'};
    } else {
        return "Unknown error";
    }
}

# Function tries to log into TT-RSS instance ($ttrss_api) with username/password saved in
# variables $ttrss_username/$ttrss_password.
# On success a session ID is saved into $ttrss_session and 1 is returned, otherwise 
# function returns 0.
sub ttrss_login {
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $post_data = '{ "op":"login", "user":"' . $ttrss_username . '","password":"' . $ttrss_password . '"}';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp = JSON->new->utf8->decode($response->content);
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            $ttrss_session = $json_resp->{'content'}->{'session_id'};
            return 1;
        } else {
            my $error = &ttrss_parse_error($json_resp);
            &print_win($error, "error");
            return 0;
        }
    } else {
        &print_win("(" . $response->code . ") " . $response->message, "error");
        return 0;
    }
}

# Function parses feed $feed and prints $limit articles into window $win on success,
# otherwise error is thrown.
# ttrss_login must be called before to obtain valid session ID
# Params: $feed, $limit
sub ttrss_parse_feed {
    my ($feed, $limit) = @_;
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $first_item = (($ttrss_last_id eq -1) ? "" : '"since_id" : '. $ttrss_last_id . ', ');
    my $post_data = '{ "sid":"' . $ttrss_session . '", "op":"getHeadlines", "feed_id": ' . 
                    $feed . ', ' . $first_item . '"limit":' . $limit . ' }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp = JSON->new->utf8->decode($response->content);
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            my @headlines = @{$json_resp->{'content'}};
            foreach my $feed (reverse @headlines) {
                $win->print("%K[%9%B" . $feed->{'feed_title'} . "%9%K]%n " . $feed->{'title'} . " %r" .
                            $feed->{'link'} . "%n", MSGLEVEL_PUBLIC);
                $ttrss_last_id = $feed->{'id'};
            }
        } else {
            my $error = &ttrss_parse_error($json_resp);
            &print_win("Couldn't fetch feed headlines: $error", "error");
            if($error eq "NOT_LOGGED_IN") {
                $ttrss_logged = 0;
            }
        }
    } else {
        &print_win("Couldn't fetch feed headlines: (" . $response->code . ") " . $response->message, "error");
    }
}

# Function creates window for ttirssi output with $win_name and saves its
# instance into $win.
# If window already exists, existing instance is saved into $win.
# Returns 1 on success, 0 otherwise.
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

# Function creates new timeout event for feed updating.
sub add_update_event {
    Irssi::timeout_remove($update_event) if $update_event;
    $update_interval = Irssi::timeout_add($update_interval, \&call_update, [ $default_feed, $article_limit ]);
}

# Function tries to perform a feed update. If current user is not logged in, calls
# ttrss_login.
# Params: Array of two elements: feed number, article limit
sub call_update {
    my $args = shift;
    my @a = @{$args};

    if($ttrss_logged) {
        &ttrss_parse_feed($a[0], $a[1]);
    } else {
        $ttrss_logged = &ttrss_login();
        if($ttrss_logged) {
            &ttrss_parse_feed($a[0], $a[1]);
        } else {
            &print_win("Couldn't get session ID", "error");
        }
    }
}

sub check_settings {
    my $rc = 1;

    if($ttrss_url eq "") {
        &print_info("%9ttirssi_url%9 is required", "error");
        $rc = 0;
    }

    if($ttrss_username eq "") {
        &print_info("%9ttirssi_username%9 is required", "error");
        $rc = 0;
    }

    if($ttrss_password eq "") {
        &print_info("%9ttirssi_password%9 is required", "error");
        $rc = 0;
    }

    if($win_name eq "") {
        &print_info("%9ttirssi_win%9 is required", "error");
        $rc = 0;
    }

    if($update_interval < 1) {
        $update_interval = 60 * 1000;
        &print_info("%9ttirssi_update_interval%9 has an invalid value (using default: 60)", "warn");
    }

    if($article_limit < 1 || $article_limit > 200) {
        $article_limit = 25;
        &print_info("%9ttirssi_article_limit%9 has an invalid value (using default: 25)", "warn");
    }

    return $rc;
}

# Get settings
$ttrss_url = Irssi::settings_get_str('ttirssi_url');
$ttrss_username = Irssi::settings_get_str('ttirssi_username');
$ttrss_password = Irssi::settings_get_str('ttirssi_password');
$win_name = Irssi::settings_get_str('ttirssi_win');
$update_interval = Irssi::settings_get_int('ttirssi_update_interval') * 1000;
$article_limit = Irssi::settings_get_int('ttirssi_article_limit');
$ttrss_api = "$ttrss_url/api/";
$ttrss_last_id = -1;
$default_feed = -3;

if(!&check_settings()) {
    &print_info("can't continue without valid settings", "error");
    return;
}

if(!&create_win()) {
    return;
}

# Try to login
$ttrss_logged = &ttrss_login();
&add_update_event();
&call_update([ $default_feed, $article_limit ]);
