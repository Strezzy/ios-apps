/** Offline native bridge for Music. Renderer credit: Ann Nguyen / TypingMind. */
import { createStage } from './stage.js';
const container = document.getElementById('case');
let stage = null;
let disposed = false;
let failed = false;
let state = {
  quality: 'hero', active: false, playing: false, reducedMotion: false,
  art: null, tiltX: 0, tiltY: 0, open: false, animateOpen: true,
  background: [0.12, 0.12, 0.14],
};
function post(value) {
  window.webkit?.messageHandlers?.musicCD?.postMessage(value);
}
function reportFailure(reason) {
  if (failed || disposed) return;
  failed = true;
  state.active = false;
  post({ type: 'failed', reason: String(reason || 'renderer-unavailable') });
}
function receive(next) {
  if (disposed || failed || !next || typeof next !== 'object' || Array.isArray(next)) return;
  const clean = {};
  for (const key of ['active','playing','reducedMotion','open','animateOpen','animateTilt']) {
    if (typeof next[key] === 'boolean') clean[key] = next[key];
  }
  for (const key of ['tiltX', 'tiltY']) {
    if (typeof next[key] === 'number' && Number.isFinite(next[key])) clean[key] = Math.max(-1, Math.min(1, next[key]));
  }
  if (next.quality === 'grid' || next.quality === 'hero') clean.quality = next.quality;
  if (next.art === null || typeof next.art === 'string') clean.art = next.art;
  if (Array.isArray(next.background) && next.background.length === 3 && next.background.every(Number.isFinite)) {
    clean.background = next.background.map(v => Math.max(0, Math.min(1, v)));
  }
  for (const key of ['epoch','artToken']) {
    if (typeof next[key] === 'string' && next[key].length <= 100) clean[key] = next[key];
  }
  if (typeof next.padding === 'number' && Number.isFinite(next.padding)) clean.padding = Math.max(0, Math.min(12, next.padding));
  const qualityChanged = clean.quality && state.quality !== clean.quality;
  Object.assign(state, clean);
  if (qualityChanged && stage) { stage.dispose(); stage = null; }
  try {
    if (!stage) {
      stage = createStage(container, { ...state }, {
        onReady: (epoch, artToken) => post({ type: 'rendered', epoch, artToken }),
        onOpen: open => post({ type: 'open', open }),
        onFail: reportFailure,
      });
    } else stage.update(clean);
  } catch (error) {
    reportFailure((error?.name || 'initialization') + ': ' + (error?.message || '').slice(0,1000));
  }
}
window.MusicCD = Object.freeze({
  receive,
  dispose() { disposed = true; stage?.dispose(); stage = null; },
  // Read-only diagnostics used by the offline renderer validation harness.
  diagnostics: () => ({ ...stage?.debug(), failed, disposed }),
});
window.addEventListener('pagehide', () => { state.active = false; stage?.update({ active: false }); });
post({ type: 'ready' });
