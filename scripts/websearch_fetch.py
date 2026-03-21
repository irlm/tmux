#!/usr/bin/env python3
"""Fetch search results from DuckDuckGo Lite and format for fzf selection."""
import sys, urllib.request, urllib.parse, re, html

if len(sys.argv) < 2 or not sys.argv[1].strip():
    sys.exit(0)

query = sys.argv[1]
# Optional site filter: --site wikipedia
if len(sys.argv) >= 4 and sys.argv[2] == "--site":
    site = sys.argv[3]
    query = f"{query} {site}"
encoded = urllib.parse.quote_plus(query)

results = []
try:
    url = f"https://lite.duckduckgo.com/lite/?q={encoded}"
    req = urllib.request.Request(url, headers={"User-Agent": "w3m/0.5.6"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        page = resp.read().decode("utf-8", errors="replace")

    # Extract result links: href="..." class='result-link'>Title</a>
    # Format: <a rel="nofollow" href="//duckduckgo.com/l/?uddg=URL" class='result-link'>Title</a>
    entries = re.findall(r'href="([^"]+)"[^>]*class=.result-link.>([^<]+)</a>', page)
    snippets = re.findall(r"class='result-snippet'>(.+?)</td>", page, re.DOTALL)

    for i, (raw_url, title) in enumerate(entries[:15]):
        title = html.unescape(title.strip())
        # Extract real URL from DDG redirect
        m = re.search(r"uddg=([^&]+)", raw_url)
        if m:
            real_url = urllib.parse.unquote(m.group(1))
        else:
            real_url = raw_url.lstrip("/")
            if not real_url.startswith("http"):
                real_url = "https://" + real_url

        snippet = ""
        if i < len(snippets):
            snippet = re.sub(r"<[^>]+>", "", snippets[i])
            snippet = html.unescape(snippet.strip())[:150]

        line = f"{i+1}. {title}"
        if snippet:
            line += f"\n   {snippet}"
        if real_url:
            line += f"\n   {real_url}"
        results.append(line)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)

if not results:
    results.append(f"No results. Enter to open in browser.\n   https://duckduckgo.com/?q={encoded}")

print("\n\n".join(results))
