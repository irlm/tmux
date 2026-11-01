#!/usr/bin/env python3
"""Fetch search results as one tab-delimited record per selectable result."""
import argparse
import html
from html.parser import HTMLParser
import sys
import urllib.error
import urllib.parse
import urllib.request

SITES = {"wikipedia": "wikipedia.org", "github": "github.com",
         "stackoverflow": "stackoverflow.com", "mdn": "developer.mozilla.org"}


class ResultsParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.results = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "a" and "result-link" in attrs.get("class", "").split():
            self.current = [attrs.get("href", ""), ""]

    def handle_data(self, data):
        if self.current is not None:
            self.current[1] += data

    def handle_endtag(self, tag):
        if tag == "a" and self.current is not None:
            raw_url, title = self.current
            absolute = urllib.parse.urljoin("https://duckduckgo.com", html.unescape(raw_url))
            parsed = urllib.parse.urlsplit(absolute)
            destination = urllib.parse.parse_qs(parsed.query).get("uddg", [absolute])[0]
            if urllib.parse.urlsplit(destination).scheme in ("http", "https"):
                self.results.append((destination, " ".join(title.split())))
            self.current = None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query")
    parser.add_argument("--site", choices=SITES)
    args = parser.parse_args(argv)
    if not args.query.strip():
        return 0
    query = args.query + (f" site:{SITES[args.site]}" if args.site else "")
    encoded = urllib.parse.quote_plus(query)
    fallback = f"https://duckduckgo.com/?q={encoded}"
    results = []
    try:
        request = urllib.request.Request(f"https://lite.duckduckgo.com/lite/?q={encoded}",
                                         headers={"User-Agent": "w3m/0.5.6"})
        with urllib.request.urlopen(request, timeout=10) as response:
            parsed = ResultsParser()
            parsed.feed(response.read().decode("utf-8", errors="replace"))
            results = parsed.results[:15]
    except (urllib.error.URLError, OSError, ValueError) as error:
        print(f"Search unavailable: {error}. Browser fallback is available.", file=sys.stderr)
    if not results:
        results = [(fallback, "Open search in browser (no fetched results)")]
    for url, title in results:
        print(f"{url.replace(chr(9), '%09').replace(chr(10), '%0A').replace(chr(13), '%0D')}\t{title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
