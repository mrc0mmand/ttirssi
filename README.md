# ttirssi

An irssi script which shows recent articles from [tt-rss](https://tt-rss.org/gitlab/fox/tt-rss/wikis/home) instance in irssi window 

## Requires
* Perl modules
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
    * `ttirssi_feeds` - space separated list of feed IDs to fetch
    * `ttirssi_categories` - space separated list of category IDs to fetch
* Reload **ttirssi**: `/script load ttirssi.pl` - if everything is set correctly, ttirssi should do an initial feed fetch

## Commands
* `ttirssi_search` - because `ttirssi_feeds` and `ttirssi_categories` require IDs as their parameters, this function should make this easier
    * Without any argument it just lists all your feeds and categories with their IDs
    * When the first argument is used, it works as a regular expression which filters feeds/categories from your feed tree
* `ttirssi_check` - this functions so far just compares your `ttirssi_feeds` and `ttirssi_categories` against your feed tree and prints out all invalid IDs (in the future it should also allow removing these IDs from aforementioned variables)

## Notes
* Currently all feed/category fetching is being done in the main irssi loop, which can lag your irssi UI for few moments or even for few seconds if you have queued many feeds/categories (or if there's a bigger network latency). This should be fixed soon, I just have to somehow solve it without threads in some elegant way.

![ttirssi screenshot](/../assets/assets/ttirssi.png?raw=true)
