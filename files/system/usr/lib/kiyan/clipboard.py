#!/usr/bin/python3
"""Plain-text clipboard cleaning shared by Kiyan desktop utilities."""
import html
import re
import urllib.parse

TRACKING = {"fbclid", "gclid", "dclid", "msclkid", "igshid", "mc_cid", "mc_eid"}


def clean_url(url):
    try:
        parts = urllib.parse.urlsplit(url)
        if parts.scheme.lower() not in ("http", "https") or not parts.netloc:
            return url
        query = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
                 if not (k.lower().startswith("utm_") or k.lower() in TRACKING)]
        return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path,
                                       urllib.parse.urlencode(query, doseq=True), parts.fragment))
    except (ValueError, UnicodeError):
        return url


def clean_text(value):
    """Convert rich text to readable text, normalize line endings, preserve Unicode."""
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"(?is)<(script|style|head|svg|noscript)\b[^>]*>.*?</\1\s*>", " ", value)
    value = re.sub(r"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6])\s*>", "\n", value)
    value = re.sub(r"(?i)</(td|th)\s*>", "\t", value)
    value = re.sub(r"<[^>]*>", "", value)
    value = html.unescape(value)
    value = re.sub(r"[\t\u00a0 ]+", " ", value)
    value = re.sub(r" *\n *", "\n", value)
    # URL punctuation remains outside the URL; math symbols and Persian ZWNJ are untouched.
    pattern = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)
    def replace(match):
        raw = match.group(0)
        suffix = ""
        while raw and raw[-1] in ".,;:!?)]}،؛؟":
            suffix = raw[-1] + suffix
            raw = raw[:-1]
        return clean_url(raw) + suffix
    return pattern.sub(replace, value).strip()
