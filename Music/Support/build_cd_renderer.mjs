#!/usr/bin/env node
/** Build-time bundler only. The IPA never fetches dependencies or remote code. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const esbuildModule = process.env.MUSIC_ESBUILD_MODULE;
const esbuild = esbuildModule ? await import(pathToFileURL(path.resolve(esbuildModule)).href) : await import('esbuild');
if (esbuild.version !== '0.25.12') throw new Error(`Expected esbuild 0.25.12, got ${esbuild.version}`);
const output = 'Resources/CDCase/music-cd.js';
const result = await esbuild.build({
  absWorkingDir: root,
  entryPoints: ['Sources/CDCaseJS/bridge.js'],
  outfile: output, bundle: true, format: 'iife', platform: 'browser',
  target: ['safari16'], minify: true, legalComments: 'inline', metafile: true,
  banner: { js: '/*! Music CD Case — Ann Nguyen / TypingMind. Three.js © 2010–2026 three.js authors (MIT). Spectral approximation: Alan Zucconi. See CDCase-ACKNOWLEDGMENTS.txt and Three-LICENSE.txt. */' },
});
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex');
const files = [...Object.keys(result.metafile.inputs),
  'Sources/CDCaseJS/vendor/LICENSE','Sources/CDCaseJS/vendor/PROVENANCE.json',
  'Support/build_cd_renderer.mjs','Resources/CDCase/index.html',
].sort();
const manifest = {
  schema: 1,
  upstreamCommit: 'efba8dfb956cca848422f18e8ede1bdf96033fca',
  threeVersion: '0.185.1', esbuildVersion: esbuild.version,
  inputs: Object.fromEntries(files.map(file => [file, sha(file)])),
  output: { path: output, sha256: sha(output) },
};
fs.writeFileSync(path.join(root,'Resources/CDCase/manifest.json'), JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({ output, bytes: fs.statSync(path.join(root,output)).size, inputs: files.length, sha256: manifest.output.sha256 },null,2));
