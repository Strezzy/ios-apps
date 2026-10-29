// SPDX-License-Identifier: GPL-3.0-or-later
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(__dirname + '/GlintBrowserScript.swift', 'utf8').split('#"""')[1].split('"""#')[0];
function anchor(href, top = 10, label = '', inArticle = false) {
  const rect = {top, bottom: top + 120, width: 320, height: 120};
  return {href, innerText: label, getAttribute: () => null, getBoundingClientRect: () => rect,
    closest: () => inArticle ? {getBoundingClientRect: () => rect} : null};
}
function posts(anchors) {
  return JSON.parse(vm.runInNewContext(source, {URL, Map, location: {href: 'https://www.instagram.com/'}, innerHeight: 800,
    document: {querySelectorAll: () => anchors}}));
}
assert.deepEqual(posts([anchor('/artist/'), anchor('/reels/'), anchor('/reels/audio/123/'), anchor('https://instagram.com.evil.test/reel/FAKE/')]), []);
assert.deepEqual(posts([anchor('javascript://instagram.com/reel/FAKE/'), anchor('https://x:y@instagram.com/reel/FAKE/')]), []);
const selected = posts([anchor('/artist/reels/AAA/?igsh=secret', 250, 'Current reel', true), anchor('/reel/AAA/'), anchor('/p/BBB/', 20), anchor('/p/ABOVE/', -200), anchor('/p/BELOW/', 1200)]);
assert.equal(selected.length, 2);
assert.equal(selected[0].url, 'https://www.instagram.com/reel/AAA/');
assert.equal(selected[0].label, 'Current reel');
assert.equal(selected[1].url, 'https://www.instagram.com/p/BBB/');
assert(!JSON.stringify(selected).includes('secret'));
assert.equal(posts(Array.from({length: 30}, (_, i) => anchor(`/p/POST${i}/`))).length, 20);
console.log('Browser post-chooser fixtures passed: visible posts, viewport order, deduplication, profile/feed exclusion, hostile URLs, tracking removal and bounded list.');
