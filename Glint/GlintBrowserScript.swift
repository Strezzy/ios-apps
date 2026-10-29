// SPDX-License-Identifier: GPL-3.0-or-later
enum GlintBrowserScript {
    // Read only links in the rendered page, on the user's explicit request.
    // Never infer a post from a CDN video URL or automatically download a feed.
    static let posts = #"""
    (() => {
      const result = new Map();
      for (const anchor of document.querySelectorAll('a[href]')) {
        let u;
        try { u = new URL(anchor.href, location.href); } catch { continue; }
        if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || u.port) continue;
        if (u.hostname !== 'instagram.com' && !u.hostname.endsWith('.instagram.com')) continue;
        const match = u.pathname.match(/^\/(?:[A-Za-z0-9_.]+\/)?(p|reels?|tv)\/([A-Za-z0-9_-]+)\/?$/);
        if (!match || match[2] === 'audio') continue;
        const rect = anchor.getBoundingClientRect();
        const article = anchor.closest('article');
        const area = article ? article.getBoundingClientRect() : rect;
        const visible = area.width > 0 && area.height > 0 && area.bottom > 0 && area.top < innerHeight;
        if (!visible) continue;
        const kind = match[1] === 'reels' ? 'reel' : match[1];
        const url = `https://www.instagram.com/${kind}/${match[2]}/`;
        const label = (anchor.getAttribute('aria-label') || anchor.innerText || '').trim().slice(0, 100);
        if (!result.has(url)) result.set(url, { url, label, distance: Math.abs(area.top - innerHeight / 3) });
      }
      return JSON.stringify([...result.values()].sort((a, b) => a.distance - b.distance).slice(0, 20));
    })()
    """#
}
