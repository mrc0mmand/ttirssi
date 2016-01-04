use strict;
use warnings;
use threads;
use threads::shared;
use Irssi;
use LWP::UserAgent;
use HTTP::Request;
use HTML::Entities;
use JSON;
use vars qw($VERSION %IRSSI);

# Nasty workaround for Irssi package warnings
{ package Irssi::Nick }
{ package Irssi::ServerConnect }
{ package Irssi::ServerSetup }
{ package Irssi::Chatnet }

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
Irssi::settings_add_str('ttirssi', 'ttirssi_feeds', '-3');
Irssi::settings_add_str('ttirssi', 'ttirssi_categories', '');

Irssi::command_bind('ttirssi_search', 'cmd_search');
Irssi::command_bind('ttirssi_list_feeds', 'cmd_list_feeds');
Irssi::command_bind('ttirssi_list_categories', 'cmd_list_categories');
Irssi::command_bind('ttirssi_list', 'cmd_list');


our $ttrss_url;
our $ttrss_api;
our $ttrss_username;
our $ttrss_password;
our $ttrss_session :shared;
our $ttrss_logged :shared;
our $win_name;
our $win_ref :shared;
our $update_interval;
our $update_event;
our $article_limit;
our $update_thread;
our @feeds :shared;
our @categories :shared;

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

sub cmd_list_feeds {
    &cmd_list('FEED');
}

sub cmd_list_categories {
    &cmd_list('CAT');
}

sub cmd_list {
    my $sel = shift;

    &print_win($sel, "info");
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

    my $win = Irssi::window_find_refnum($win_ref);

    if(not defined $type) {
        $win->print($message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        $win->print("%RError: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'info') {
        $win->print("%GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'warn') {
        $win->print("%YWarning: %n" . $message, MSGLEVEL_CLIENTCRAP)
    } elsif($type eq 'feed') {
        $win->print($message, MSGLEVEL_PUBLIC);
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
    my ($feed, $last, $limit, $is_cat) = @_;

    if(&check_win()) {
        return;
    }

    my $rc = -1;
    my $ua = new LWP::UserAgent;
    $ua->agent("ttirssi $VERSION");
    my $request = HTTP::Request->new("POST" => $ttrss_api);
    my $first_item = (($last eq -1) ? "" : '"since_id" : '. $last . ', ');
    $is_cat = ($is_cat) ? "true" : "false";
    my $post_data = '{ "sid":"' . $ttrss_session . '", "op":"getHeadlines", "feed_id": ' . 
                    $feed . ', ' . $first_item . '"limit":' . $limit . ', "is_cat":' . $is_cat . ' }';
    $request->content($post_data);

    my $response = $ua->request($request);
    if($response->is_success) {
        my $json_resp;
        eval {
            $json_resp = JSON->new->utf8->decode($response->content);
        };

        if($@) {
            &print_win("Received malformed JSON response from server - check server configuration", "error");
            return $rc;
        }

        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            $rc = -2;
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

                &print_win("%K[%9%B" . $feed_title . "%9%K]%n " . $title . " %r" . $url . "%n", "feed");

                $rc = $feed->{'id'};
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

    return $rc;
}

# Function creates window for ttirssi output with $win_name and saves its
# instance into $win.
# If window already exists, existing instance is saved into $win.
# Returns 0 on success, 1 otherwise.
sub create_win {
    # If desired window already exists, don't create a new one
    my $win = Irssi::window_find_name($win_name);
    if($win) {
        &print_info("Will use an existing window '$win_name'", "info");
        $win_ref = $win->{'refnum'};
        return 0;
    }

    $win = Irssi::Windowitem::window_create($win_name, 1);
    if(not $win) {
        &print_info("Failed to create window '$win_name'", "error");
        return 1;
    }

    &print_info("Created a new window '$win_name'", "info");
    $win->set_name($win_name);
    $win_ref = $win->{'refnum'};
    return 0;
}

sub check_win {
    if(not defined $win_ref || !Irssi::window_find_refnum($win_ref)) {
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
    $update_event = Irssi::timeout_add($update_interval, \&call_update, undef);
}

sub remove_update_event {
    Irssi::timeout_remove($update_event) if $update_event;
}

sub call_update {
    if(not defined $update_thread) {
        $update_thread = threads->create(\&prepare_update);
    } elsif(!$update_thread->is_running() || $update_thread->is_joinable()) {
        if($update_thread->is_running()) {
            $update_thread->join();
        }

        $update_thread = threads->create(\&prepare_update);
    } else {
        &print_win("Previous update is still in progress, skipping current one", "warn");
    }
}

sub prepare_update {
    if($ttrss_logged) {
        &do_update();
    } else {
        my $loginrc = &ttrss_login();
        if($loginrc eq 0) {
            $ttrss_logged = 1;
            &do_update();
        } elsif($loginrc eq 1) {
            &print_win("Recoverable error - next try in ". ($update_interval / 1000) . " seconds", "warn");
        } else {
            &print_win("Unrecoverable error - reload ttirssi script after fixing the issue", "error");
            &remove_update_event();
            return;
        }
    }
}

sub do_update {
    my $rc;

    &print_info("Session ID: $ttrss_session", "info");
    foreach my $feed (@feeds) {
        &print_info("Feed ID: " . $feed->{'last_id'}, "info");
        $rc = &ttrss_parse_feed($feed->{'id'}, $feed->{'last_id'}, $article_limit, 0);
        if($rc eq -1) {
            &print_win("Next try in " . ($update_interval / 1000) . " seconds", "warn");
            return;
        } elsif($rc ne -2) {
            $feed->{'last_id'} = $rc;
        }
    }

    foreach my $cat (@categories) {
        $rc = &ttrss_parse_feed($cat->{'id'}, $cat->{'last_id'}, $article_limit, 1);
        if($rc eq -1) {
            &print_win("Next try in " . ($update_interval / 1000) . " seconds", "warn");
            return;
        } elsif($rc ne -2) {
            $cat->{'last_id'} = $rc;
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
my $feedstr = Irssi::settings_get_str('ttirssi_feeds');
for(split(/\s+/, $feedstr)) {
    if($_ =~ /^\-?\d+\z/) {
        my %f :shared;
        $f{"id"} = $_;
        $f{"last_id"} = -1;
        push(@feeds, \%f);
    } else {
        &print_info("Invalid feed ID '$_', skipping...", "warn");
    }
}

my $catstr = Irssi::settings_get_str('ttirssi_categories');
for(split(/\s+/, $catstr)) {
    if($_ =~ /^\-?\d+\z/) {
        my %c :shared;
        $c{"id"} = $_;
        $c{"last_id"} = -1;
        push(@categories, \%c);
    } else {
        &print_info("Invalid category ID '$_', skipping...", "warn");
    }
}

$ttrss_url = Irssi::settings_get_str('ttirssi_url');
$ttrss_username = Irssi::settings_get_str('ttirssi_username');
$ttrss_password = Irssi::settings_get_str('ttirssi_password');
$win_name = Irssi::settings_get_str('ttirssi_win');
$update_interval = Irssi::settings_get_int('ttirssi_update_interval') * 1000;
$article_limit = Irssi::settings_get_int('ttirssi_article_limit');
$ttrss_api = "$ttrss_url/api/";

if(&check_settings()) {
    &print_info("Can't continue without valid settings", "error");
    return;
}

if(&create_win()) {
    return;
}

&add_update_event();
&call_update();
