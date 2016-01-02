use strict;
use warnings;
use Irssi;
use LWP::UserAgent;
use HTTP::Request;
use HTML::Entities;
use JSON;
use vars qw($VERSION %IRSSI);

$VERSION = '0.02';
%IRSSI = (
    authors => 'Frantisek Sumsal',
    contact => 'frantisel@sumsal.cz',
    name    => 'ttirssi',
    description => 'An irssi script which shows recent articles from tt-rss instance in irssi window',
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

Irssi::command_bind('twirssi_search', 'cmd_search');

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

sub cmd_search {
    my $searchstr = shift;

    if(!$ttrss_logged && &ttrss_login()) {
        return;
    }

    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $post_data = '{ "sid":"' . $ttrss_session . '", "op":"getFeedTree" }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp;
        eval {
            $json_resp = JSON->new->utf8->decode($response->content);
        };

        if($@) {
            &print_win("Received malformed JSON response from server - check server configuration", "error");
            return;
        }

        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            &print_win("Search results for: $searchstr", "info");
            foreach my $cat (@{$json_resp->{'content'}{'categories'}{'items'}}) {
                if($cat->{'name'} =~ /$searchstr/) {
                    &print_win("Type: CAT, ID: %C" . $cat->{'bare_id'} . "%n, Name: " . $cat->{'name'});
                }

                foreach my $feed (@{$cat->{'items'}}) {
                    if($feed->{'name'} =~ /$searchstr/) {
                        &print_win("Type: FEED, ID: %M" . $feed->{'bare_id'} . "%n, Name: " . $feed->{'name'});
                    }
                }
            }
        } else {
            my $error = &ttrss_parse_error($json_resp);
            &print_win("Couldn't fetch feeds: $error", "error");
            if($error eq "NOT_LOGGED_IN") {
                $ttrss_logged = 0;
            }
        }
    } else {
        &print_win("Couldn't fetch feeds: (" . $response->code . ") " . $response->message, "error");
    }
}

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

    if(&check_win()) {
        return;
    }

    if(not defined $type) {
        $win->print($message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        $win->print("%RError: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'info') {
        $win->print("%GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'warn') {
        $win->print("%YWarning: %n" . $message, MSGLEVEL_CLIENTCRAP)
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
# On success a session ID is saved into $ttrss_session and 0 is returned, otherwise 
# function returns non-zero integer (1 => recoverable error, 2 => unrecoverable).
sub ttrss_login {
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $post_data = '{ "op":"login", "user":"' . $ttrss_username . '","password":"' . $ttrss_password . '" }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp;
        eval {
            $json_resp = JSON->new->utf8->decode($response->content);
        };

        if($@) {
            &print_win("Received malformed JSON response from server - check server configuration", "error");
            return 1;
        }

        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            $ttrss_session = $json_resp->{'content'}->{'session_id'};
            return 0;
        } else {
            my $rc = 2;
            my $error = &ttrss_parse_error($json_resp);

            if($error eq "LOGIN_ERROR") {
                &print_win("Incorrect username/password", "error");
            } elsif($error eq "API_DISABLED") {
                &print_win("API is disabled", "error");
            } else {
                # Probably recoverable error
                &print_win($error, "error");
                $rc = 1;
            }

            return $rc;
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

    if(&check_win()) {
        return;
    }

    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $first_item = (($ttrss_last_id eq -1) ? "" : '"since_id" : '. $ttrss_last_id . ', ');
    my $post_data = '{ "sid":"' . $ttrss_session . '", "op":"getHeadlines", "feed_id": ' . 
                    $feed . ', ' . $first_item . '"limit":' . $limit . ' }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp;
        eval {
            $json_resp = JSON->new->utf8->decode($response->content);
        };

        if($@) {
            &print_win("Received malformed JSON response from server - check server configuration", "error");
            return;
        }

        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            my @headlines = @{$json_resp->{'content'}};
            foreach my $feed (reverse @headlines) {
                # Replace all % with %% to prevent interpreting %X sequences as color codes
                # There must be a better way...
                my $url = $feed->{'link'};
                $url =~ s/%/%%/g;
                my $title = $feed->{'title'};
                decode_entities($title);
                $title =~ s/%/%%/g;
                $title =~ s/\n/ /g;
                my $feed_title = $feed->{'feed_title'};
                $feed_title =~ s/%/%%/g;

                $win->print("%K[%9%B" . $feed_title . "%9%K]%n " . $title . " %r" .
                            $url . "%n", MSGLEVEL_PUBLIC);

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
# Returns 0 on success, 1 otherwise.
sub create_win {
    # If desired window already exists, don't create a new one
    $win = Irssi::window_find_name($win_name);
    if($win) {
        &print_info("Will use an existing window '$win_name'", "info");
        return 0;
    }

    $win = Irssi::Windowitem::window_create($win_name, 1);
    if(not $win) {
        &print_info("Failed to create window '$win_name'", "error");
        return 1;
    }

    &print_info("Created a new window '$win_name'", "info");
    $win->set_name($win_name);
    return 0;
}

sub check_win {
    if(!$win || !Irssi::window_find_refnum($win->{'refnum'})) {
        &print_info("Missing window '$win_name'", "error");
        if(&create_win()) {
            &remove_update_event();
            return 1;
        }
    }

    return 0;
}

# Function creates new timeout event for feed updating.
sub add_update_event {
    Irssi::timeout_remove($update_event) if $update_event;
    $update_event = Irssi::timeout_add($update_interval, \&call_update, [ $default_feed, $article_limit ]);
}

sub remove_update_event {
    Irssi::timeout_remove($update_event) if $update_event;
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
        my $loginrc = &ttrss_login();
        if($loginrc eq 0) {
            $ttrss_logged = 1;
            &ttrss_parse_feed($a[0], $a[1]);
        } elsif($loginrc eq 1) {
            &print_win("Recoverable error - next try in ". ($update_interval / 1000) . " seconds", "warn");
        } else {
            &print_win("Unrecoverable error - reload ttirssi script after fixing the issue", "error");
            &remove_update_event();
            return;
        }
    }
}

sub check_settings {
    my $rc = 0;

    if($ttrss_url eq "") {
        &print_info("%9ttirssi_url%9 is required but not set", "error");
        $rc = 1;
    }

    if($ttrss_username eq "") {
        &print_info("%9ttirssi_username%9 is required but not set", "error");
        $rc = 1;
    }

    if($ttrss_password eq "") {
        &print_info("%9ttirssi_password%9 is required but not set", "error");
        $rc = 1;
    }

    if($win_name eq "") {
        &print_info("%9ttirssi_win%9 is required but not set", "error");
        $rc = 1;
    }

    if($update_interval < (15 * 1000)) {
        $update_interval = 60 * 1000;
        &print_info("%9ttirssi_update_interval%9 has an invalid value [min: 15] (using default: 60)", "warn");
    }

    if($article_limit < 1 || $article_limit > 200) {
        $article_limit = 25;
        &print_info("%9ttirssi_article_limit%9 has an invalid value [min: 1, max: 200] (using default: 25)", "warn");
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

if(&check_settings()) {
    &print_info("Can't continue without valid settings", "error");
    return;
}

if(&create_win()) {
    return;
}

&add_update_event();
&call_update([ $default_feed, $article_limit ]);
