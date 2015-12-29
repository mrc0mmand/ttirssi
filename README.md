# ttirssi

An irssi script which shows recent articles from [tt-rss](https://tt-rss.org/gitlab/fox/tt-rss/wikis/home) instance in irssi window 

## Requires
* Perl modules
    * JSON
    * HTTP::Request
    * HTML::Entities
    * LWP::UserAgent
* tt-rss
    * Version 1.6.0 or later with enabled API (Preferences -> Enable API access)

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
* Reload **ttirssi**: `/script load ttirssi.pl` - if everything is set correctly, ttirssi should do an initial feed fetch

![ttirssi screenshot](/../assets/assets/ttirssi.png?raw=true)
