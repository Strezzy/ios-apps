# SPDX-License-Identifier: GPL-3.0-or-later
"""Small, portable provenance records. Never save cookies, headers or CDN URLs."""
import contextlib
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import urlsplit, urlunsplit


def instagram_url(value):
    try:
        parts = urlsplit(str(value or ''))
        if parts.scheme not in {'http', 'https'} or parts.username or parts.password or parts.port:
            return None
        host = (parts.hostname or '').lower()
        if host != 'instagram.com' and not host.endswith('.instagram.com'):
            return None
        return urlunsplit(('https', 'www.instagram.com', parts.path, '', ''))
    except ValueError:
        return None


def post_url(value):
    url = instagram_url(value)
    if not url:
        return None
    match = re.fullmatch(r'/(?:[A-Za-z0-9_.]+/)?(p|reels?|tv)/([A-Za-z0-9_-]+)/?', urlsplit(url).path)
    if not match or match[2] == 'audio':
        return None
    kind = 'reel' if match[1] == 'reels' else match[1]
    return f'https://www.instagram.com/{kind}/{match[2]}/'


def profile_url(value):
    url = instagram_url(value)
    if not url:
        return None
    name = urlsplit(url).path.strip('/')
    if not re.fullmatch(r'[A-Za-z0-9_.]{1,30}', name) or name.lower() in {
            'p', 'reel', 'reels', 'tv', 'explore', 'accounts', 'direct', 'stories', 'about', 'legal'}:
        return None
    return f'https://www.instagram.com/{name}/'


def record(info, fallback_url=None):
    post = next((p for x in [info.get('webpage_url'), info.get('original_url'), fallback_url]
                 if (p := post_url(x))), None)
    if not post:
        return None
    creator = profile_url(info.get('channel_url')) or profile_url(info.get('uploader_url'))
    if not creator:
        # Instagram's channel is the username; uploader_id is often a numeric PK.
        username = info.get('channel')
        if not username:
            candidate = info.get('uploader_id')
            username = candidate if isinstance(candidate, str) and not candidate.isdecimal() else None
        if isinstance(username, str):
            creator = profile_url(f'https://www.instagram.com/{username}/')
    return {'version': 1, 'postURL': post, 'creatorURL': creator,
            'username': urlsplit(creator).path.strip('/') if creator else None,
            'title': str(info.get('title') or '')[:300] or None}


def sidecar(path):
    path = Path(path)
    key = hashlib.sha256(unicodedata.normalize('NFC', path.name).encode()).hexdigest()[:24]
    return path.parent / f'.glint-origin-{key}.json'


def save(info, root, fallback_url=None):
    value = record(info, fallback_url)
    if not value or not info.get('filepath'):
        return
    path = Path(info['filepath']).resolve()
    if not path.is_relative_to(Path(root).resolve()) or not path.is_file():
        return
    destination = sidecar(path)
    temporary = destination.with_suffix('.tmp')
    try:
        temporary.write_text(json.dumps(value, ensure_ascii=False) + '\n', encoding='utf-8')
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def capture_origins(root, fallback_url):
    import yt_dlp
    original = yt_dlp.YoutubeDL.run_all_pps

    def run(self, key, info, **kwargs):
        result = original(self, key, info, **kwargs)
        if key == 'after_move':
            try:
                save(result, root, fallback_url)
            except (OSError, ValueError, TypeError):
                self.report_warning('The download was saved, but its original-post record could not be written.')
        return result

    yt_dlp.YoutubeDL.run_all_pps = run
    try:
        yield
    finally:
        yt_dlp.YoutubeDL.run_all_pps = original
