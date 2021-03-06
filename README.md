# ttirssi

An irssi script which shows recent articles from [tt-rss](https://tt-rss.org/gitlab/fox/tt-rss/wikis/home) instance in irssi window 

## Requirements
* Perl modules
    * AnyEvent
    * JSON
    * HTTP::Request
    * HTML::Entities
    * LWP::UserAgent
* tt-rss
    * Version 1.7.6 or later with enabled API (Preferences -> Enable API access)

## Installation
* Create a directory for irssi scripts (if it doesn't already exist): `mkdir -p ~/.irssi/scripts`
* Download `ttirssi.pl` script into the `scripts` directory

## Configuration
* Load **ttirssi**: `/script load ttirssi.pl` - it creates an initial configuration and informs you about missing values
* Set required variables:
    * `ttirssi_url` - URL where your tt-rss instance is located
    * `ttirssi_username` - username of your tt-rss account
    * `ttirssi_password` - password of your tt-rss account
* Optionally you can override default values of following variables:
    * `ttirssi_win` - name of **ttirssi** window (default: ttirssi)
    * `ttirssi_update_interval` - delay between feed updates in seconds (default: 60)
    * `ttirssi_article_limit` - max amount of articles which will be fetched during each update (default: 25)
    * `ttirssi_feeds` - space separated list of feed IDs to fetch (default: -3)
    * `ttirssi_categories` - space separated list of category IDs to fetch (default: *empty*)
    * `ttirssi_hilight_words` - space separated list of words which you will be hilighted for
    * `ttirssi_hilight_type` - look of a hilighted message (default: word)
        * `word` - hilight only a matched word in a message
        * `line` - hilight an entire message with a matched word
* Reload **ttirssi**: `/ttirssi_reload` - if everything is set correctly, ttirssi should do an initial feed fetch

## Commands
* `ttirssi_search` - because `ttirssi_feeds` and `ttirssi_categories` require IDs as their parameters, this function should make this easier
    * Without any argument it just lists all your feeds and categories with their IDs
    * When the first argument is used, it works as a regular expression which filters feeds/categories from your feed tree
* `ttirssi_check` - this functions compares your `ttirssi_feeds` and `ttirssi_categories` against your feed tree and prints out all invalid IDs
    * Options:
        * `-remove` - remove all invalid IDs from their variables after the check is done
        * `-listall` - list all IDs (valid and invalid) along with their category/feed names and their validity status
* `ttirssi_reload` - reloads internal structures and loads new values of `ttirssi_*` settings

## UI
* Optionally you can enable statusbar item `ttirssi_status`, which will show you how much time the last update took
    * For instance command `/statusbar topic add -after topicbarstart ttirssi_status` places status indicator at the beginning of the topic bar
    * More info about `statusbar` command can be found in the [official irssi documentation](https://irssi.org/documentation/startup/#statusbar)


![ttirssi screenshot](/../assets/assets/ttirssi.png?raw=true)
