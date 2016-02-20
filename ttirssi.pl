use strict;
use warnings;
use AnyEvent;
use Irssi;
use Irssi::TextUI;
use LWP::UserAgent;
use HTTP::Request;
use HTML::Entities;
use JSON;
use vars qw($VERSION %IRSSI);

$VERSION = '0.09';
%IRSSI = (
    authors => 'Frantisek Sumsal',
    contact => 'frantisek@sumsal.cz',
    name    => 'ttirssi',
    description => 'An irssi script which shows recent articles from tt-rss instance in irssi window',
    license => 'BSD',
    url     => 'https://github.com/mrc0mmand/ttirssi',
    changed => 'Sat Feb  6 23:39:02 CET 2016',
);

my %api;
my %settings;
my $win;
my $update_status;
my $update_event;
my @feeds;
my @categories;

sub cmd_search {
    my $searchstr = shift;

    if(!$api{'is_logged'} && ttrss_login()) {
        return;
    }

    my $post_data = '{ "sid":"' . $api{'session'}. '", "op":"getFeedTree" }';
    my $response = http_post_request($api{'url'}, $post_data);
    my $json_resp;

    if(get_response_json(\$response, \$json_resp) == 0) {
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            print_win("Search results for: $searchstr", "info");
            foreach my $cat (@{$json_resp->{'content'}{'categories'}{'items'}}) {
                if($cat->{'name'} =~ /$searchstr/) {
                    print_win("Type: CAT, ID: %C" . $cat->{'bare_id'} . "%n, Name: " . $cat->{'name'});
                }

                foreach my $feed (@{$cat->{'items'}}) {
                    if($feed->{'name'} =~ /$searchstr/) {
                        print_win("Type: FEED, ID: %M" . $feed->{'bare_id'} . "%n, Name: " . $feed->{'name'});
                    }
                }
            }
        } else {
            my $error = ttrss_parse_error($json_resp);
            print_win("Couldn't fetch feeds: $error", "error");
            if($error eq "NOT_LOGGED_IN") {
                $api{'is_logged'} = 0;
            }
        }
    }

    return;
}

sub cmd_check {
    my $data = shift;

    if(!$api{'is_logged'} && ttrss_login()) {
        return;
    }

    my ($href) = Irssi::command_parse_options('ttirssi_check', $data);
    my $listall = exists $href->{'listall'};
    my $remove = exists $href->{'remove'};
    my $post_data = '{ "sid":"' . $api{'session'}. '", "op":"getFeedTree" }';
    my $response = http_post_request($api{'url'}, $post_data);
    my $catstr = "";
    my $feedstr = "";
    my $catstr_orig = "";
    my $feedstr_orig = "";
    my $json_resp;

    if(get_response_json(\$response, \$json_resp) == 0) {
        my @c = @categories;
        my @f = @feeds;

        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            foreach my $cat (@{$json_resp->{'content'}{'categories'}{'items'}}) {
                if(array_remove_id(\@c, $cat->{'bare_id'}) && $listall) {
                    print_win("CAT:%C " . $cat->{'bare_id'} . "%n - " . $cat->{'name'}, "info");
                }

                foreach my $feed (@{$cat->{'items'}}) {
                    if(array_remove_id(\@f, $feed->{'bare_id'}) && $listall) {
                        print_win("FEED:%M " . $feed->{'bare_id'} . "%n - " . $feed->{'name'}, "info");
                    }
                }
            }

            if($remove) {
                $catstr = Irssi::settings_get_str('ttirssi_categories');
                $feedstr = Irssi::settings_get_str('ttirssi_feeds');
                $catstr_orig = $catstr;
                $feedstr_orig = $feedstr;
            }

            if($#c ne -1) {
                my $str = "";
                print_win("Invalid category IDs: ", "warn");
                foreach my $cat (@c) {
                    $str .= "%C " . $cat->{'id'} . "%n ";
                    if($remove) {
                        $catstr =~ s/((?<=\s)|(?<=^))$cat->{'id'}(?=(\s|$))//g;
                    }
                }

                print_win($str);
            }

            if($#f ne -1) {
                my $str = "";
                print_win("Invalid feed IDs: ", "warn");
                foreach my $feed (@f) {
                    $str .= "%M " . $feed->{'id'} . "%n ";
                    if($remove) {
                        $feedstr =~ s/((?<=\s)|(?<=^))$feed->{'id'}(?=(\s|$))//g;
                    }
                }

                print_win($str);
            }

            if($remove && ($catstr ne $catstr_orig || $feedstr ne $feedstr_orig)) {
                # Clean excessive spaces
                $catstr =~ s/\s+/ /g;
                $catstr =~ s/^\s+|\s+$//g;
                $feedstr =~ s/\s+/ /g;
                $feedstr =~ s/^\s+|\s+$//g;

                Irssi::settings_set_str('ttirssi_categories', $catstr);
                Irssi::settings_set_str('ttirssi_feeds', $feedstr);
                Irssi::signal_emit('setup changed');
                print_win("Settings have been updated, calling reload...", "info");

                reload_settings();
            }

            if($#c eq -1 && $#f eq -1) {
                print_win("All IDs are correct", "info");
            }
        } else {
            my $error = ttrss_parse_error($json_resp);
            print_win("Couldn't fetch feeds: $error", "error");
            if($error eq "NOT_LOGGED_IN") {
                $api{'is_logged'} = 0;
            }
        }
    }

    return;
}

sub cmd_reload {
    print_info("Reloading settings...", "info");
    reload_settings();
}

sub sb_status {
    my ($sb_item, $get_size_only) = @_;
    $update_status = "%K?%n" if not $update_status;
    $sb_item->default_handler($get_size_only, "{sb $update_status}", '', 0);
}

sub sb_status_update {
    my ($status) = @_;
    my $c;

    if($status < 1) {
        $c = "%G";
    } elsif($status < 2) {
        $c = "%Y";
    } else {
        $c = "%R";
    }

    $update_status = "$c$status%n";
    Irssi::statusbar_items_redraw('ttirssi_status');
}

sub array_remove_id {
    my ($a, $id) = @_;
    my $rc = 0;

    for(my $i = 0; $i <= $#{$a}; $i++) {
        if($a->[$i]->{'id'} == $id) {
            splice(@$a, $i, 1);
            $rc = 1;
        }
    }

    return $rc;
}

sub print_info {
    my ($message, $type) = @_;

    if(not defined $type) {
        Irssi::print("%g[ttirssi]%n " . $message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'error') {
        Irssi::print("%g[ttirssi] %RError: %n" . $message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'info') {
        Irssi::print("%g[ttirssi] %GInfo: %n" . $message, MSGLEVEL_CLIENTCRAP);
    } elsif($type eq 'warn') {
        Irssi::print("%g[ttirssi] %YWarning: %n" . $message, MSGLEVEL_CLIENTCRAP);
    } else {
        Irssi::print("%g[ttirssi]%n " . $message, MSGLEVEL_CLIENTCRAP);
    }

    return;
}

sub print_win {
    my ($message, $type) = @_;
    if(check_win()) {
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
    } elsif($type eq 'hilight') {
        $win->print($message, MSGLEVEL_PUBLIC|MSGLEVEL_MSGS|MSGLEVEL_HILIGHT);
    } else {
        $win->print($message, MSGLEVEL_PUBLIC);
    }

    return;
}

sub http_post_request {
    # TODO: Blocking I/O in request could cause some problems
    my ($url, $data) = @_;
    my $ua = LWP::UserAgent->new;
    $ua->agent("ttirssi $VERSION");
    $ua->timeout(5);
    my $request = HTTP::Request->new("POST" => $url);
    $request->content($data);

    return $ua->request($request);
}

sub get_response_json {
    my ($response, $data) = @_;
    $response = $$response;

    if($response->is_success) {
        my $json_resp;
        eval {
            $json_resp = JSON->new->utf8->decode($response->content);
        };

        if($@) {
            print_win("Received malformed JSON response from server - check server configuration", "error");
            return 1;
        }

        $$data = $json_resp;
        return 0;
    } else {
        print_win("Couldn't fetch feeds: (" . $response->code . ") " . $response->message, "error");
    }

    return 1;
}

sub ttrss_parse_error {
    my $json_resp = shift;

    if(exists $json_resp->{'content'}{'error'}) {
        return $json_resp->{'content'}{'error'};
    } else {
        return "Unknown error";
    }
}

# Function tries to log into TT-RSS instance ($api{'url'}) with username/password saved in
# variables $api{'username'}/$api{'password'}.
# On success a session ID is saved into $api{'session'} and 0 is returned, otherwise 
# function returns non-zero integer (1 => recoverable error, 2 => unrecoverable).
sub ttrss_login {
    my $post_data = '{ "op":"login", "user":"' . $api{'username'} . '","password":"' . $api{'password'} . '" }';
    my $response = http_post_request($api{'url'}, $post_data);
    my $json_resp;

    if(get_response_json(\$response, \$json_resp) == 0) {
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            $api{'session'} = $json_resp->{'content'}->{'session_id'};
            return 0;
        } else {
            my $rc = 2;
            my $error = ttrss_parse_error($json_resp);

            if($error eq "LOGIN_ERROR") {
                print_win("Incorrect username/password", "error");
            } elsif($error eq "API_DISABLED") {
                print_win("API is disabled", "error");
            } else {
                # Probably recoverable error
                print_win($error, "error");
                $rc = 1;
            }

            return $rc;
        }
    }

    return 1;
}

# Function parses feed $feed and prints $limit articles into window $win on success,
# otherwise error is thrown.
# ttrss_login must be called before to obtain valid session ID
# Params: $feed, $limit
sub ttrss_parse_feed {
    my ($feed, $last_id, $limit, $is_cat) = @_;

    if(check_win()) {
        return;
    }

    my $rc = -1;
    my $first_item = (($last_id eq -1) ? "" : '"since_id" : '. $last_id . ', ');
    $is_cat = ($is_cat) ? "true" : "false";
    my $post_data = '{ "sid":"' . $api{'session'} . '", "op":"getHeadlines", "feed_id": ' . 
                    $feed . ', ' . $first_item . '"limit":' . $limit . ', "is_cat":' . 
                    $is_cat . ', "order_by":"feed_dates" }';
    my $response = http_post_request($api{'url'}, $post_data);
    my $json_resp;

    if(get_response_json(\$response, \$json_resp) == 0) {
        if(exists $json_resp->{'status'} && $json_resp->{'status'} eq 0) {
            $rc = -2;
            my @headlines = @{$json_resp->{'content'}};

            foreach my $feed (@headlines) {
                # Replace all % with %% to prevent interpreting %X sequences as color codes
                # There must be a better way...
                my $hilight = 0;
                my $url = $feed->{'link'};
                $url =~ s/%/%%/g;
                my $title = $feed->{'title'};
                decode_entities($title);
                $title =~ s/%/%%/g;
                $title =~ s/\n/ /g;
                foreach(@{$settings{'hilight_words'}}) {
                    if($title =~ /$_/) {
                        $hilight = 1;
                        if($settings{'hilight_type'} eq 'line') {
                            # Break loop if the hilight type is set to 'line',
                            # we will hilight the entire line anyway
                            last;
                        } else {
                            $title =~ s/(?'word'$_)/%9$settings{'hilight_color'}$+{word}%n/gi;
                        }
                    }
                }
                my $feed_title = $feed->{'feed_title'};
                $feed_title =~ s/%/%%/g;

                if($hilight && $settings{'hilight_type'} eq 'line') {
                    print_win("%9" . $settings{'hilight_color'} . "[" . $feed_title . "] " . $title . " " .
                              $url . "%n", "hilight");
                } else {
                    print_win("%K[%9%B" . $feed_title . "%9%K]%n " . $title . " %r" .
                              $url . "%n", (($hilight) ? "hilight" : ""));
                }

                if($rc < $feed->{'id'}) {
                    $rc = $feed->{'id'};
                }
            }
        } else {
            my $error = ttrss_parse_error($json_resp);
            print_win("Couldn't fetch feed headlines: $error", "error");
            if($error eq "NOT_LOGGED_IN") {
                $api{'is_logged'} = 0;
            }
        }
    }

    return $rc;
}

# Function creates window for ttirssi output with $win_name and saves its
# instance into $win.
# If window already exists, existing instance is saved into $win.
# Returns 0 on success, 1 otherwise.
sub create_win {
    # If desired window already exists, don't create a new one
    $win = Irssi::window_find_name($settings{'win_name'});
    if($win) {
        print_info("Will use an existing window '$settings{'win_name'}'", "info");
        return 0;
    }

    $win = Irssi::Windowitem::window_create($settings{'win_name'}, 1);
    if(not $win) {
        print_info("Failed to create window '$settings{'win_name'}'", "error");
        return 1;
    }

    print_info("Created a new window '$settings{'win_name'}'", "info");
    $win->set_name($settings{'win_name'});

    return 0;
}

sub check_win {
    # TODO: Storing and later using any Irssi object may result in use-after-free related crash
    if(!$win || !Irssi::window_find_refnum($win->{'refnum'})) {
        if(create_win() != 0) {
            print_info("Can't continue without valid window", "error");
            remove_update_event();
            return 1;
        }
    }

    return 0;
}

# Function creates new timeout event for feed updating.
sub add_update_event {
    undef $update_event;
    $update_event = AnyEvent->timer(after => 1,
                                    interval => $settings{'update_interval'},
                                    cb => \&call_update);

    return;
}

sub remove_update_event {
    undef $update_event;

    return;
}

# Function tries to perform a feed update. If current user is not logged in, calls
# ttrss_login.
# Params: Array of two elements: feed number, article limit
sub call_update {
    my $sttime = time;

    if($api{'is_logged'}) {
        do_update();
    } else {
        my $loginrc = ttrss_login();
        if($loginrc eq 0) {
            $api{'is_logged'} = 1;
            do_update();
        } elsif($loginrc eq 1) {
            print_win("Recoverable error - next try in ". $settings{'update_interval'} . " seconds", "warn");
        } else {
            print_win("Unrecoverable error - reload ttirssi script after fixing the issue", "error");
            remove_update_event();
        }
    }

    sb_status_update((time - $sttime));
    return;
}

sub do_update {
    my $rc;

    foreach my $feed (@feeds) {
        $rc = ttrss_parse_feed($feed->{'id'}, $feed->{'last_id'}, $settings{'article_limit'}, 0);
        if($rc eq -1) {
            print_win("Next try in " . $settings{'update_interval'} . " seconds", "warn");
            return;
        } elsif($rc ne -2) {
            $feed->{'last_id'} = $rc;
        }
    }

    foreach my $cat (@categories) {
        $rc = ttrss_parse_feed($cat->{'id'}, $cat->{'last_id'}, $settings{'article_limit'}, 1);
        if($rc eq -1) {
            print_win("Next try in " . $settings{'update_interval'} . " seconds", "warn");
            return;
        } elsif($rc ne -2) {
            $cat->{'last_id'} = $rc;
        }
    }

    return;
}


sub check_settings {
    my $rc = 0;

    if($api{'inst_url'} eq "") {
        print_info("%9ttirssi_url%9 is required but not set", "error");
        $rc = 1;
    }

    if($api{'username'} eq "") {
        print_info("%9ttirssi_username%9 is required but not set", "error");
        $rc = 1;
    }

    if($api{'password'} eq "") {
        print_info("%9ttirssi_password%9 is required but not set", "error");
        $rc = 1;
    }

    if($settings{'win_name'} eq "") {
        print_info("%9ttirssi_win%9 is required but not set", "error");
        $rc = 1;
    }

    if($settings{'update_interval'} < 15) {
        $settings{'update_interval'} = 60;
        print_info("%9ttirssi_update_interval%9 has an invalid value [min: 15] (using default: 60)", "warn");
    }

    if($settings{'article_limit'} < 1 || $settings{'article_limit'} > 200) {
        $settings{'article_limit'} = 25;
        print_info("%9ttirssi_article_limit%9 has an invalid value [min: 1, max: 200] (using default: 25)", "warn");
    }

    return $rc;
}

# Get settings
sub load_settings {
    my $feedstr = Irssi::settings_get_str('ttirssi_feeds');
    for(split(/\s+/, $feedstr)) {
        if($_ =~ /^\-?\d+\z/) {
            push(@feeds, { "id" => $_, "last_id" => -1 });
        } else {
            print_info("Invalid feed ID '$_', skipping...", "warn");
        }
    }

    my $catstr = Irssi::settings_get_str('ttirssi_categories');
    for(split(/\s+/, $catstr)) {
        if($_ =~ /^\-?\d+\z/) {
            push(@categories, { "id" => $_, "last_id" => -1 });
        } else {
            print_info("Invalid category ID '$_', skipping...", "warn");
        }
    }

    $api{'inst_url'} = Irssi::settings_get_str('ttirssi_url');
    $api{'username'} = Irssi::settings_get_str('ttirssi_username');
    $api{'password'}= Irssi::settings_get_str('ttirssi_password');
    $settings{'win_name'} = Irssi::settings_get_str('ttirssi_win');
    $settings{'update_interval'} = Irssi::settings_get_int('ttirssi_update_interval');
    $settings{'article_limit'} = Irssi::settings_get_int('ttirssi_article_limit');
    $api{'url'} = $api{'inst_url'} . "/api/";
    $api{'session'} = "";
    $api{'is_logged'} = 0;
    $settings{'hilight_color'} = Irssi::settings_get_str('hilight_color');
    $settings{'hilight_words'} = [ split /\s+/, Irssi::settings_get_str('ttirssi_hilight_words') ];
    $settings{'hilight_type'} = lc(Irssi::settings_get_str('ttirssi_hilight_type'));
    $settings{'hilight_type'} =~ s/^\s+|\s+$//g;

    if(check_settings()) {
        print_info("Can't continue without valid settings", "error");
        return 1;
    }

    return 0;
}

sub reload_settings {
    remove_update_event();

    my @feeds_bak = @feeds;
    my @categories_bak = @categories;
    undef %api;
    undef @feeds;
    undef @categories;

    if(load_settings() == 0) {
        print_info("Settings have been reloaded", "info");
        add_update_event();
    } else {
        exit 1;
    }

    copy_last_id(\@feeds_bak, \@feeds);
    copy_last_id(\@categories_bak, \@categories);

    return;
}

sub copy_last_id {
    my ($old, $new) = @_;

    foreach my $oit (@$old) {
        foreach my $nit (@$new) {
            if($nit->{'id'} == $oit->{'id'}) {
                $nit->{'last_id'} = $oit->{'last_id'};
            }
        }
    }
}

# Init
Irssi::settings_add_str('ttirssi', 'ttirssi_url', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_username', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_password', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_win', 'ttirssi');
Irssi::settings_add_int('ttirssi', 'ttirssi_update_interval', '60');
Irssi::settings_add_int('ttirssi', 'ttirssi_article_limit', '25');
Irssi::settings_add_str('ttirssi', 'ttirssi_feeds', '-3');
Irssi::settings_add_str('ttirssi', 'ttirssi_categories', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_hilight_words', '');
Irssi::settings_add_str('ttirssi', 'ttirssi_hilight_type', 'word');

Irssi::command_bind('ttirssi_search', 'cmd_search');
Irssi::command_bind('ttirssi_check', 'cmd_check');
Irssi::command_bind('ttirssi_reload', 'cmd_reload');
Irssi::command_set_options('ttirssi_check', '-listall -remove');

Irssi::statusbar_item_register('ttirssi_status', 0, 'sb_status');
Irssi::statusbars_recreate_items();
sb_status_update(0);

if(load_settings() != 0 || create_win() != 0) {
    return 1;
}

add_update_event();
