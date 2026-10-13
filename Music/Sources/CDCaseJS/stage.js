/**
 * Music's offline adaptation of Ann Nguyen's CD Case, built with TypingMind.
 * Source: https://github.com/annnguyentt/vibe-coding/tree/efba8dfb956cca848422f18e8ede1bdf96033fca/cd-case
 * Original reuse permission and unmodified sources: Support/Upstream/CDCase.
 * Changes: native bridge, bounded render budgets, lifecycle, album textures,
 * transparent compositing, accessibility, and demand-driven animation.
 */
import * as THREE from './vendor/three.module.js';
import { cassetteTrayGeometry, cassetteLidGeometry, cassetteBodyGeometry, cassetteShellGeometry, cassetteReelGeometry, CASSETTE_FRAG, REEL_FRAG } from './cassetteGeometry.js';
import { CASE, HALF, HINGE, discGeometry, lidGeometry, trayGeometry } from './caseGeometry.js';
import {
  BACKDROP_FRAG,
  BACKDROP_VERT,
  BRIGHT_FRAG,
  COPY_FRAG,
  DISC_FRAG,
  DISC_VERT,
  FINAL_FRAG,
  ROD_FRAG,
  ROD_VERT,
  ROOM_BAKE_FRAG,
  SCREEN_VERT,
  SHEET_FRAG,
  SHEET_VERT,
  STREAK_FRAG,
} from './shaders.js';

const FOV = 28;
const IOR = 1.59;
const ABSORB = [0.0042, 0.003, 0.0026];
const DEPTH = 14;
const BACKDROP_Z = -70;
const LIGHT = new THREE.Vector3(-0.3, 0.48, 1).normalize();
const SPIN = THREE.MathUtils.degToRad(18);
const SPIN_EASE = 0.9;
const FIT = 0.94;

const MSAA = 4;

const STARS = 1.6;
const STAR_THRESHOLD = 2.0;

const REST = 2.6;
const AGAIN = 5.5;
const OPEN_HOLD = 0.25;

const GRAB_RATE = 0.008;
const GRAB_YAW = 0.9;
const GRAB_TILT = 0.45;
const GRAB_K = 16;
const GRAB_C = 5.5;
const TAP_SLOP = 6;

const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const clamp01 = (x) => clamp(x, 0, 1);
const lerp = (a, b, t) => a + (b - a) * t;
const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

function curve(frames) {
  const n = frames.length;
  const ts = frames.map((f) => f[0]);
  const vs = frames.map((f) => f[1]);
  const d = [];
  for (let i = 0; i < n - 1; i++) d.push((vs[i + 1] - vs[i]) / (ts[i + 1] - ts[i]));
  const m = new Array(n).fill(0);
  for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  for (let i = 0; i < n - 1; i++) {
    if (d[i] === 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    const a = m[i] / d[i];
    const b = m[i + 1] / d[i];
    const s = a * a + b * b;
    if (s > 9) {
      const k = 3 / Math.sqrt(s);
      m[i] = k * a * d[i];
      m[i + 1] = k * b * d[i];
    }
  }
  return (t) => {
    if (t <= ts[0]) return vs[0];
    if (t >= ts[n - 1]) return vs[n - 1];
    let i = 0;
    while (t > ts[i + 1]) i++;
    const h = ts[i + 1] - ts[i];
    const u = (t - ts[i]) / h;
    const u2 = u * u;
    const u3 = u2 * u;
    return (
      (2 * u3 - 3 * u2 + 1) * vs[i] +
      (u3 - 2 * u2 + u) * h * m[i] +
      (-2 * u3 + 3 * u2) * vs[i + 1] +
      (u3 - u2) * h * m[i + 1]
    );
  };
}

const OPEN_ANGLE = 3.05;
const OPEN_T = 2.3;
const OPEN = {
  yaw: curve([
    [0, 0],
    [0.55, 0.3],
    [1.0, 0.85],
    [1.2, 2.0],
    [1.41, 3.4],
    [1.63, 4.9],
    [1.85, 6.05],
    [2.05, 6.36],
    [2.3, 2 * Math.PI],
  ]),
  lid: curve([
    [0, 0],
    [0.97, 0],
    [1.2, 0.45],
    [1.41, 1.35],
    [1.63, 2.3],
    [1.85, 2.92],
    [2.05, 3.12],
    [2.3, OPEN_ANGLE],
  ]),
  spread: curve([
    [0, 0],
    [1.12, 0],
    [1.9, 0.9],
    [2.3, 1],
  ]),
  pitch: curve([
    [0, 0],
    [1.35, 0],
    [2.3, -0.1],
  ]),
};

const CLOSE_T = 1.95;
const CLOSE = {
  lid: curve([
    [0, OPEN_ANGLE],
    [0.22, 1.75],
    [0.48, 1.55],
    [1.05, 1.08],
    [1.42, 0.6],
    [1.6, 0.26],
    [1.7, 0],
    [1.78, 0.07],
    [1.88, 0],
  ]),
  spread: curve([
    [0, 1],
    [0.3, 0.92],
    [1.2, 0.55],
    [1.72, 0],
  ]),
  yaw: curve([
    [0, 0],
    [0.5, 0.2],
    [1.3, 0.12],
    [1.88, 0],
  ]),
  pitch: curve([
    [0, -0.1],
    [1.6, -0.05],
    [1.7, 0.035],
    [1.82, -0.01],
    [1.95, 0],
  ]),
  roll: curve([
    [0, 0],
    [0.8, -0.05],
    [1.95, 0],
  ]),
};

function sway(t, motion) {
  return {
    y: 1.8 * Math.sin(t * 1.1) * motion,
    yaw: -0.2 + (0.1 * Math.sin(t * 0.9) + 0.03 * Math.sin(t * 2.1)) * motion,
    pitch: -0.12 + 0.045 * Math.sin(t * 0.7) * motion,
    roll: 0.03 + 0.018 * Math.sin(t * 0.5) * motion,
    lid: 0,
    spread: 0,
  };
}

export function createStage(container, control, { onOpen, onReady, onFail }) {
  let disposed = false;
  let failed = false;
  let raf = 0;
  const fatal = (reason) => {
    if (failed || disposed) return;
    failed = true; control.active = false;
    cancelAnimationFrame(raf); raf = 0;
    onFail?.(reason);
  };
  const grid = control.quality === 'grid';
  const cassette = control.medium === 'cassette';
  const halfHeight = cassette ? 50 : HALF;
  const ROOM_SIZE = 256;
  const targetFPS = grid ? 18 : 30;
  const getSpin = () => control.playing && !control.reducedMotion;
  // The native user decides when to open the lid; no timed presentation tour.
  const getPaused = () => true;
  let motion = 0;
  let dirty = true;
  let firstFrame = true;
  let frameCount = 0;
  let artGeneration = 0;
  let currentArt = null;
  let previousArt = null;
  let artMix = 1;
  let artKey = null;
  let artLoading = false;
  let announcedFrame = '';
  let artworkCompletedAt = 0;
  const startedAt = performance.now();
  let firstFrameMs = null;
  let fittedExtent = 0;
  let fitRatio = 1;
  const background = new THREE.Vector3(0.018, 0.018, 0.023);
  const disc = { artIn: 16.2, printOut: 59.1 };

  const canvas = document.createElement('canvas');
  canvas.className = 'cd-canvas';
  canvas.setAttribute('role', 'img');
  canvas.setAttribute(
    'aria-label',
    cassette ? 'A clear cassette case with two spinning reels. Tap to open, or drag to turn.' : 'A clear CD jewel case with its disc spinning inside. Tap the case to open it, or drag it to turn it.',
  );
  container.appendChild(canvas);

  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: false,
      alpha: true,
      premultipliedAlpha: true,
      powerPreference: grid ? 'low-power' : 'default',
    });
  } catch {
    canvas.remove();
    onFail?.();
    return null;
  }
  renderer.debug.onShaderError = (gl, program, vertex, fragment) => {
    const details = [gl.getProgramInfoLog(program),gl.getShaderInfoLog(vertex),gl.getShaderInfoLog(fragment)].filter(Boolean).join(' | ');
    fatal('shader-compile: ' + details.slice(0,1800));
  };
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.autoClear = false;
  renderer.setClearColor(0xffffff, 0);
  const hdr =
    renderer.extensions.has('EXT_color_buffer_float') || renderer.extensions.has('EXT_color_buffer_half_float');
  const target = (samples, depthBuffer = false) =>
    new THREE.WebGLRenderTarget(1, 1, {
      type: hdr ? THREE.HalfFloatType : THREE.UnsignedByteType,
      samples,
      depthBuffer,
      stencilBuffer: false,
      resolveDepthBuffer: false,
    });
  // Antialias the actual offscreen geometry, not just the final full-screen
  // quad. The old grid rendered these surfaces at 1x with zero MSAA samples.
  const gl = renderer.getContext();
  const supportedSamples = Array.from(gl.getInternalformatParameter(gl.RENDERBUFFER,
    hdr ? gl.RGBA16F : gl.RGBA8, gl.SAMPLES) || []);
  const sampleCount = Math.max(0, ...supportedSamples.filter(n => n <= MSAA));
  const rtPage = target(sampleCount, true);
  const rt = [target(sampleCount, true), target(sampleCount, true)];
  const rtBright = target(0);
  const rtStarA = target(0);
  const rtStarB = target(0);

  const camera = new THREE.PerspectiveCamera(FOV, 1, 10, 4000);
  const opaque = new THREE.Scene();
  const glass = new THREE.Scene();
  const hits = new THREE.Scene();

  const disposables = [];
  const track = (d) => {
    disposables.push(d);
    return d;
  };

  const screenCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const screenQuad = track(new THREE.PlaneGeometry(2, 2));
  const pass = (frag, uniforms) => {
    const material = track(
      new THREE.ShaderMaterial({
        uniforms,
        vertexShader: SCREEN_VERT,
        fragmentShader: frag,
        depthTest: false,
        depthWrite: false,
      }),
    );
    const scene = new THREE.Scene();
    scene.add(new THREE.Mesh(screenQuad, material));
    return { scene, material };
  };
  const copyMat = track(
    new THREE.ShaderMaterial({
      uniforms: { uTex: { value: null } },
      vertexShader: SCREEN_VERT,
      fragmentShader: COPY_FRAG,
      depthTest: false,
      depthWrite: false,
    }),
  );
  const copyQuad = new THREE.Mesh(screenQuad, copyMat);
  copyQuad.frustumCulled = false;
  copyQuad.renderOrder = -10;
  const picked = {
    uTex: { value: rtPage.texture },
    uTexInside: { value: rtPage.texture },
    uRect: { value: new THREE.Vector4(0, 0, 0, 0) },
  };
  const bright = pass(BRIGHT_FRAG, {
    ...picked,
    uTexel: { value: new THREE.Vector2() },
    uThreshold: { value: STAR_THRESHOLD },
  });
  const streak = pass(STREAK_FRAG, {
    uTex: { value: null },
    uStep: { value: new THREE.Vector2() },
    uFalloff: { value: 0.7 },
  });
  const final = pass(FINAL_FRAG, {
    ...picked,
    uStarA: { value: rtStarA.texture },
    uStarB: { value: rtStarB.texture },
    uStars: { value: grid || !hdr ? 0 : STARS },
    uBackground: { value: background },
  });

  const roomRT = new THREE.WebGLCubeRenderTarget(ROOM_SIZE, {
    type: hdr ? THREE.HalfFloatType : THREE.UnsignedByteType,
    generateMipmaps: true,
    minFilter: THREE.LinearMipmapLinearFilter,
    magFilter: THREE.LinearFilter,
    depthBuffer: false,
  });
  const bake = pass(ROOM_BAKE_FRAG, { uFace: { value: 0 }, uSize: { value: ROOM_SIZE } });
  const bakeRoom = () => {
    for (let face = 0; face < 6; face++) {
      bake.material.uniforms.uFace.value = face;
      renderer.setRenderTarget(roomRT, face);
      renderer.render(bake.scene, screenCam);
    }
    renderer.setRenderTarget(null);
  };
  bakeRoom();

  const shadowOf = {
    uBackground: { value: background },
    uLight: { value: LIGHT.clone() },
    uTrayInv: { value: new THREE.Matrix4() },
    uLidInv: { value: new THREE.Matrix4() },
    uScale: { value: 1 },
  };
  const backdrop = new THREE.Mesh(
    track(new THREE.PlaneGeometry(8000, 8000)),
    track(new THREE.ShaderMaterial({ uniforms: shadowOf, vertexShader: BACKDROP_VERT, fragmentShader: cassette ? BACKDROP_FRAG.replaceAll('vec2(73.0)','vec2(73.0,50.0)').replace('float r = length(h.xy);','float r = roundBox(h.xy,vec2(64.0,39.0),5.0)+60.0;') : BACKDROP_FRAG })),
  );
  backdrop.position.z = BACKDROP_Z;
  opaque.add(backdrop);
  const depthOnly = track(new THREE.MeshBasicMaterial({ colorWrite: false }));
  glass.add(copyQuad);

  const samples = 2;

  const rodMaterial = () =>
    track(
      new THREE.ShaderMaterial({
        uniforms: {
          uBehind: { value: null },
          uRoom: { value: roomRT.texture },
          uRoomSize: { value: ROOM_SIZE },
          uProj: { value: camera.projectionMatrix },
          uDepth: { value: DEPTH },
          uIor: { value: IOR },
          uSamples: { value: samples },
          uAbsorb: { value: new THREE.Vector3(...ABSORB) },
        },
        vertexShader: ROD_VERT,
        fragmentShader: ROD_FRAG,
      }),
    );
  const sheetMaterial = () =>
    track(
      new THREE.ShaderMaterial({
        uniforms: {
          uIor: { value: IOR },
          uAbsorb: { value: new THREE.Vector3(...ABSORB) },
        },
        vertexShader: SHEET_VERT,
        fragmentShader: SHEET_FRAG,
        transparent: true,
        depthWrite: false,
        polygonOffset: true,
        polygonOffsetFactor: 1,
        polygonOffsetUnits: 4,
        blending: THREE.CustomBlending,
        blendSrc: THREE.OneFactor,
        blendDst: THREE.OneMinusSrcAlphaFactor,
        blendSrcAlpha: THREE.OneFactor,
        blendDstAlpha: THREE.OneMinusSrcAlphaFactor,
      }),
    );

  const fixed = (mesh, scene) => {
    mesh.matrixAutoUpdate = false;
    mesh.visible = false;
    scene.add(mesh);
    return mesh;
  };

  const hitPlane = track(new THREE.PlaneGeometry(CASE, halfHeight*2));
  const hitMat = track(new THREE.MeshBasicMaterial({ side: THREE.DoubleSide }));

  function buildCase(art) {
    const tray = cassette ? cassetteTrayGeometry() : trayGeometry();
    const lid = cassette ? cassetteLidGeometry() : lidGeometry();
    const discGeo = cassette ? cassetteBodyGeometry() : discGeometry();
    for (const g of [tray.rods, tray.sheets, lid.rods, lid.sheets, discGeo]) track(g);

    const trayRodMat = rodMaterial();
    const lidRodMat = rodMaterial();
    const discMat = track(
      new THREE.ShaderMaterial({
        uniforms: {
          uArt: { value: art },
          uArtPrevious: { value: art },
          uArtMix: { value: 1 },
          uArtIn: { value: disc.artIn },
          uPrintOut: { value: disc.printOut },
        },
        vertexShader: DISC_VERT,
        fragmentShader: cassette ? CASSETTE_FRAG : DISC_FRAG,
      }),
    );

    const item = {
      trayRods: fixed(new THREE.Mesh(tray.rods, trayRodMat), glass),
      traySheets: fixed(new THREE.Mesh(tray.sheets, sheetMaterial()), glass),
      lidRods: fixed(new THREE.Mesh(lid.rods, lidRodMat), glass),
      lidSheets: fixed(new THREE.Mesh(lid.sheets, sheetMaterial()), glass),
      discMesh: fixed(new THREE.Mesh(discGeo, discMat), opaque),
      discDepth: fixed(new THREE.Mesh(discGeo, depthOnly), glass),
      hitTray: fixed(new THREE.Mesh(hitPlane, hitMat), hits),
      hitLid: fixed(new THREE.Mesh(hitPlane, hitMat), hits),
      trayRodMat,
      lidRodMat,
      mCase: new THREE.Matrix4(),
      mLid: new THREE.Matrix4(),
      depthTray: 0,
      depthLid: 0,
    };
    item.reels=[];
    if (cassette) {
      const shell=cassetteShellGeometry(); track(shell.rods); track(shell.sheets);
      item.tapeRods=fixed(new THREE.Mesh(shell.rods,trayRodMat),glass);
      item.tapeSheets=fixed(new THREE.Mesh(shell.sheets,sheetMaterial()),glass);
      item.tapeSheets.renderOrder=1;
      const reel=track(cassetteReelGeometry());
      const material=track(new THREE.ShaderMaterial({vertexShader:DISC_VERT,fragmentShader:REEL_FRAG}));
      item.reels=[-30,30].map(x=>({x,mesh:fixed(new THREE.Mesh(reel,material),opaque),depth:fixed(new THREE.Mesh(reel,depthOnly),glass)}));
      for(const r of item.reels) r.depth.renderOrder=-5;
    }
    item.traySheets.renderOrder = 1;
    item.lidSheets.renderOrder = 1;
    item.discDepth.renderOrder = -5;
    return item;
  }

  const pointer = { x: 0, y: 0, over: false };
  const lean = { x: 0, y: 0 };
  const grab = {
    active: false,
    start: null,
    last: null,
    x: 0,
    y: 0,
    vx: 0,
    vy: 0,
    flick: { x: 0, y: 0 },
    moved: 0,
    dist: 0,
  };
  const st = {
    t: 0,
    clock: 0,
    rest: REST,
    phase: 'rest',
    phaseAt: 0,
    auto: false,
    closeAfter: false,
    spin: 0,
    spinRate: 0,
    open: false,
  };
  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  let item = null;
  let last = 0;
  let view = { w: 1, h: 1, openScale: 1, baseDistance: 400 };

  const setOpenFlag = (on) => {
    if (st.open === on) return;
    st.open = on;
    onOpen?.(on);
  };

  function startOpen(auto) {
    if (st.phase !== 'rest') return;
    st.phase = 'opening';
    st.phaseAt = st.t;
    st.auto = auto;
    setOpenFlag(true);
  }
  function startClose() {
    if (st.phase === 'opening') {
      st.auto = true;
      st.closeAfter = true;
      return;
    }
    if (st.phase !== 'open') return;
    st.phase = 'closing';
    st.phaseAt = st.t;
    setOpenFlag(false);
  }
  function toggleOpen(on = !(st.phase === 'opening' || st.phase === 'open')) {
    if (!item) return;
    // A renewed Open intent cancels a Close queued during the opening curve.
    if (on) { st.closeAfter = false; st.auto = false; }
    if (control.reducedMotion || control.animateOpen === false) {
      st.phase = on ? 'open' : 'rest';
      st.phaseAt = st.t;
      st.closeAfter = false;
      st.auto = false;
      setOpenFlag(!!on);
    } else if (on) startOpen(false);
    else startClose();
    dirty = true;
    schedule();
  }

  function showPose(t) {
    motion = control.reducedMotion || !control.playing ? 0 : (grid ? 0.14 : 0.35);
    const p = sway(t, motion);
    const since = t - st.phaseAt;
    if (st.phase === 'opening') {
      const q = Math.min(since, OPEN_T);
      p.yaw = lerp(p.yaw, 0, clamp01(q / 1.0)) + OPEN.yaw(q);
      p.lid = OPEN.lid(q);
      p.spread = OPEN.spread(q);
      p.pitch = lerp(p.pitch, OPEN.pitch(q), clamp01(q / 1.45));
      p.roll *= 1 - clamp01(q / 1.45);
    } else if (st.phase === 'open') {
      p.yaw = 0.06 * Math.sin(t * 0.6) * motion;
      p.pitch = -0.1 + 0.02 * Math.sin(t * 0.8) * motion;
      p.roll = 0;
      p.lid = OPEN_ANGLE + 0.025 * Math.sin(t * 1.3) * motion;
      p.spread = 1;
    } else if (st.phase === 'closing') {
      const q = Math.min(since, CLOSE_T);
      const back = clamp01((q - 0.9) / (CLOSE_T - 0.9));
      const rest = easeInOut(back);
      p.yaw = lerp(CLOSE.yaw(q), p.yaw, rest);
      p.pitch = lerp(CLOSE.pitch(q), p.pitch, rest);
      p.roll = lerp(CLOSE.roll(q), p.roll, rest);
      p.lid = CLOSE.lid(q);
      p.spread = CLOSE.spread(q);
    }
    return p;
  }

  const _q = new THREE.Quaternion();
  const _e = new THREE.Euler(0, 0, 0, 'XYZ');
  const _v = new THREE.Vector3();
  const _s = new THREE.Vector3();
  const _m = new THREE.Matrix4();
  const _h = new THREE.Matrix4();
  const _hi = new THREE.Matrix4();
  function place(p) {
    const s = lerp(1, view.openScale, p.spread);
    _e.set(p.pitch + lean.x + grab.x, p.yaw + lean.y + grab.y, p.roll);
    _q.setFromEuler(_e);
    // Cassette lid folds forward/down around the lower horizontal edge.
    // Raise the open case to centre the vertical silhouette in the artwork.
    _v.set(cassette ? 0 : HALF * s * p.spread * 0.92,
      p.y + (cassette ? halfHeight * s * p.spread * .92 : 0), 0);
    item.mCase.compose(_v, _q, _s.setScalar(s));
    if(cassette) {
      _h.makeTranslation(0, -49, 4);
      _hi.makeTranslation(0, 49, -4);
      _m.makeRotationX(p.lid);
    } else {
      _h.makeTranslation(HINGE.x, 0, HINGE.z);
      _hi.makeTranslation(-HINGE.x, 0, -HINGE.z);
      _m.makeRotationY(-p.lid);
    }
    item.mLid.copy(item.mCase).multiply(_h).multiply(_m).multiply(_hi);

    item.trayRods.matrix.copy(item.mCase);
    item.traySheets.matrix.copy(item.mCase);
    item.lidRods.matrix.copy(item.mLid);
    item.lidSheets.matrix.copy(item.mLid);
    item.discMesh.matrix.copy(item.mCase).multiply(_m.makeRotationZ(cassette ? 0 : -st.spin));
    item.discDepth.matrix.copy(item.discMesh.matrix);
    if(cassette) {
      for(const mesh of [item.tapeRods,item.tapeSheets]) { mesh.matrix.copy(item.mCase);mesh.matrixWorld.copy(mesh.matrix);mesh.visible=true; }
      for(const r of item.reels) {
        r.mesh.matrix.copy(item.mCase).multiply(_m.makeTranslation(r.x,1,0)).multiply(_h.makeRotationZ(-st.spin*3));
        r.depth.matrix.copy(r.mesh.matrix);
        for(const mesh of [r.mesh,r.depth]) {mesh.matrixWorld.copy(mesh.matrix);mesh.visible=true;}
      }
    }
    item.hitTray.matrix.copy(item.mCase);
    item.hitLid.matrix.copy(item.mLid).multiply(_m.makeTranslation(0, 0, 4));
    for (const o of [
      item.trayRods,
      item.traySheets,
      item.lidRods,
      item.lidSheets,
      item.discMesh,
      item.discDepth,
      item.hitTray,
      item.hitLid,
    ]) {
      o.matrixWorld.copy(o.matrix);
      o.visible = true;
    }
    _v.set(0, 0, -2).applyMatrix4(item.mCase).applyMatrix4(camera.matrixWorldInverse);
    item.depthTray = _v.z;
    _v.set(0, 0, 4).applyMatrix4(item.mLid).applyMatrix4(camera.matrixWorldInverse);
    item.depthLid = _v.z;

    shadowOf.uTrayInv.value.copy(item.mCase).invert();
    shadowOf.uLidInv.value.copy(item.mLid).invert();
    shadowOf.uScale.value = s;
  }

  const caseAt = (x, y) => {
    if (!item) return false;
    ndc.set(x, y);
    raycaster.setFromCamera(ndc, camera);
    return raycaster.intersectObjects([item.hitTray, item.hitLid], false).length > 0;
  };
  const hovering = () => pointer.over && !grab.active && caseAt(pointer.x, pointer.y);

  function frame(dt) {
    st.t += dt * (st.phase === 'opening' ? (Number(control.entranceSpeed) || 1) : 1);
    const { t } = st;

    const want = getSpin() ? SPIN : 0;
    st.spinRate += (want - st.spinRate) * (1 - Math.exp(-dt * SPIN_EASE * 3));
    st.spin += st.spinRate * dt;

    const hover = pointer.over && !grab.active;
    const ax = (hover ? pointer.y * 0.22 : 0) + clamp(Number(control.tiltX) || 0, -1, 1) * (grid ? 0.19 : 0.42);
    const ay = (hover ? -pointer.x * 0.35 : 0) + clamp(Number(control.tiltY) || 0, -1, 1) * (grid ? 0.27 : 0.75);
    const k = 1 - Math.exp(-dt * 4);
    lean.x += (ax - lean.x) * k;
    lean.y += (ay - lean.y) * k;
    if (!grab.active) {
      grab.vx += (-GRAB_K * grab.x - GRAB_C * grab.vx) * dt;
      grab.vy += (-GRAB_K * grab.y - GRAB_C * grab.vy) * dt;
      grab.x += grab.vx * dt;
      grab.y += grab.vy * dt;
    }

    if (artMix < 1) {
      artMix = Math.min(1, artMix + dt / (control.reducedMotion ? 0.001 : 0.32));
      item.discMesh.material.uniforms.uArtMix.value = artMix;
      if (artMix === 1 && previousArt && previousArt !== currentArt) {
        previousArt.dispose();
        previousArt = currentArt;
        item.discMesh.material.uniforms.uArtPrevious.value = currentArt;
      }
    }
    const since = t - st.phaseAt;
    if (st.phase === 'opening' && since >= OPEN_T) {
      st.phase = 'open';
      control.entranceSpeed=1;
      st.phaseAt = t;
    } else if (st.phase === 'closing' && since >= CLOSE_T) {
      st.phase = 'rest';
      st.phaseAt = t;
      st.clock = 0;
      st.rest = AGAIN;
      if (control.open) startOpen(false);
    }

    const held = grab.active || hovering() || (st.phase === 'open' && !st.auto);
    const showing = !getPaused() && !held;
    if (st.phase === 'open' && (st.closeAfter || (st.auto && showing && t - st.phaseAt >= OPEN_HOLD))) {
      st.closeAfter = false;
      startClose();
    }
    if (showing) {
      st.clock += dt;
      if (st.phase === 'rest' && st.clock >= st.rest) startOpen(true);
    }

    place(showPose(t));
    fitPoseInsideArtwork();
    draw();
    // Announce only a frame with the requested cover. A pooled renderer must
    // never reveal the previous album while the replacement image is decoding.
    const frameKey = String(control.epoch || '') + ':' + String(control.artToken || '');
    if (!artLoading && control.artToken !== 'pending' && !failed && (firstFrame || announcedFrame !== frameKey)) {
      firstFrame = false; announcedFrame = frameKey;
      if (firstFrameMs === null) firstFrameMs = performance.now() - startedAt;
      onReady?.(control.epoch, control.artToken);
    }
  }

  const fitPoint = new THREE.Vector3();
  function fitPoseInsideArtwork() {
    const tanHalf = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
    const reserve = Math.max(3, Math.min(view.w, view.h) * 0.012);
    const safeX = 1 - 2 * reserve / Math.max(1, view.w);
    const safeY = 1 - 2 * reserve / Math.max(1, view.h);
    let distance = view.baseDistance;
    // Conservative bounds cover the rounded rails, hinge and sheets. They
    // also include depth, so perspective foreshortening cannot clip a corner.
    for (const matrix of [item.mCase, item.mLid]) {
      for (let i = 0; i < 8; i++) {
        fitPoint.set(i & 1 ? HALF + 1.25 : -HALF - 1.25,
          i & 2 ? halfHeight + 1.25 : -halfHeight - 1.25, i & 4 ? 7 : -7).applyMatrix4(matrix);
        distance = Math.max(distance,
          fitPoint.z + Math.abs(fitPoint.x) / (tanHalf * camera.aspect * safeX),
          fitPoint.z + Math.abs(fitPoint.y) / (tanHalf * safeY));
      }
    }
    camera.position.z = distance * 1.002;
    camera.updateMatrixWorld();
    fitRatio = view.baseDistance / camera.position.z;
    fittedExtent = 0;
    for (const matrix of [item.mCase, item.mLid]) {
      for (let i = 0; i < 8; i++) {
        fitPoint.set(i & 1 ? HALF + 1.25 : -HALF - 1.25,
          i & 2 ? halfHeight + 1.25 : -halfHeight - 1.25, i & 4 ? 7 : -7).applyMatrix4(matrix).project(camera);
        fittedExtent = Math.max(fittedExtent, Math.abs(fitPoint.x), Math.abs(fitPoint.y));
      }
    }
  }

  const _c = new THREE.Vector3();
  function caseRect(w, h) {
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    for (const m of [item.mCase, item.mLid]) {
      for (let i = 0; i < 8; i++) {
        _c.set(i & 1 ? HALF + 3 : -HALF - 3, i & 2 ? halfHeight + 3 : -halfHeight - 3, i & 4 ? 7 : -7);
        _c.applyMatrix4(m).project(camera);
        x0 = Math.min(x0, _c.x);
        x1 = Math.max(x1, _c.x);
        y0 = Math.min(y0, _c.y);
        y1 = Math.max(y1, _c.y);
      }
    }
    const pad = 0.04 * Math.max(x1 - x0, y1 - y0) + 0.02;
    const px = (v) => Math.round(((v + 1) / 2) * w);
    const py = (v) => Math.round(((v + 1) / 2) * h);
    const r = {
      x: clamp(px(x0 - pad), 0, w),
      y: clamp(py(y0 - pad), 0, h),
      x1: clamp(px(x1 + pad), 0, w),
      y1: clamp(py(y1 + pad), 0, h),
    };
    return r.x1 > r.x && r.y1 > r.y ? r : null;
  }

  const groups = [];
  function draw() {
    frameCount++;
    renderer.setRenderTarget(rtPage);
    renderer.clear();
    renderer.render(opaque, camera);

    groups.length = 0;
    groups.push({ depth: item.depthTray, rods: item.trayRods, sheets: item.traySheets, mat: item.trayRodMat });
    groups.push({ depth: item.depthLid, rods: item.lidRods, sheets: item.lidSheets, mat: item.lidRodMat });
    groups.sort((a, b) => a.depth - b.depth);
    const glassMeshes = [item.trayRods, item.traySheets, item.lidRods, item.lidSheets, ...(cassette ? [item.tapeRods,item.tapeSheets] : [])];
    const w = rtPage.width;
    const h = rtPage.height;
    const rect = caseRect(w, h);
    let from = rtPage;
    if (rect) {
      for (const r of rt) {
        r.scissor.set(rect.x, rect.y, rect.x1 - rect.x, rect.y1 - rect.y);
        r.scissorTest = true;
      }
      groups.forEach((g, i) => {
        const into = rt[i % 2];
        renderer.setRenderTarget(into);
        renderer.clear();
        copyMat.uniforms.uTex.value = from.texture;
        for (const m of glassMeshes) m.visible = m === g.rods || m === g.sheets || (cassette && g.rods === item.trayRods && (m === item.tapeRods || m === item.tapeSheets));
        g.mat.uniforms.uBehind.value = from.texture;
        renderer.render(glass, camera);
        from = into;
      });
      for (const r of rt) r.scissorTest = false;
    }
    for (const m of glassMeshes) m.visible = true;
    picked.uTexInside.value = from.texture;
    if (rect) picked.uRect.value.set(rect.x / w, rect.y / h, rect.x1 / w, rect.y1 / h);
    else picked.uRect.value.set(0, 0, 0, 0);

    if (!grid && hdr) {
    bright.material.uniforms.uTexel.value.set(1 / rtBright.width, 1 / rtBright.height);
    renderer.setRenderTarget(rtBright);
    renderer.render(bright.scene, screenCam);
    streak.material.uniforms.uTex.value = rtBright.texture;
    streak.material.uniforms.uStep.value.set(1.5 / rtBright.width, 0);
    renderer.setRenderTarget(rtStarA);
    renderer.render(streak.scene, screenCam);
    streak.material.uniforms.uStep.value.set(0, 1.5 / rtBright.height);
    renderer.setRenderTarget(rtStarB);
    renderer.render(streak.scene, screenCam);

    }
    renderer.setRenderTarget(null);
    renderer.render(final.scene, screenCam);
  }

  function layout() {
    const w = container.clientWidth || 1;
    const h = container.clientHeight || 1;
    renderer.setSize(w, h, false);
    const size = renderer.getDrawingBufferSize(new THREE.Vector2());
    rtPage.setSize(size.x, size.y);
    for (const r of rt) r.setSize(size.x, size.y);
    const hw = grid ? 1 : Math.max(1, Math.round(size.x / 2));
    const hh = grid ? 1 : Math.max(1, Math.round(size.y / 2));
    rtBright.setSize(hw, hh);
    rtStarA.setSize(hw, hh);
    rtStarB.setSize(hw, hh);
    camera.aspect = w / h;
    const tanHalf = Math.tan(THREE.MathUtils.degToRad(FOV / 2));
    const padding = clamp(Number(control.padding) || 0, 0, 12);
    const fitH = CASE / FIT / 2 / tanHalf * h / Math.max(1, h - padding * 2);
    const fitW = (CASE * 1.065) / 2 / (tanHalf * camera.aspect) * w / Math.max(1, w - padding * 2);
    const dist = Math.max(fitH, fitW);
    camera.position.set(0, 0, dist);
    camera.lookAt(0, 0, 0);
    camera.clearViewOffset();
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
    const across = 2 * dist * tanHalf * camera.aspect;
    view = { w, h, openScale: Math.min(1.04, across / (CASE * 2.25)), baseDistance: dist };
    dirty = true;
    schedule();
  }

  const ro = new ResizeObserver(() => layout());
  ro.observe(container);
  const contextLost = (event) => {
    event.preventDefault();
    fatal('context-lost');
  };
  canvas.addEventListener('webglcontextlost', contextLost);

  const toNdc = (e) => {
    const r = container.getBoundingClientRect();
    return [((e.clientX - r.left) / r.width) * 2 - 1, 1 - ((e.clientY - r.top) / r.height) * 2];
  };
  const onMove = (e) => {
    [pointer.x, pointer.y] = toNdc(e);
    pointer.over = true;
    dirty = true; schedule();
    if (grab.active) {
      const dx = e.clientX - grab.last.x;
      const dy = e.clientY - grab.last.y;
      grab.last = { x: e.clientX, y: e.clientY };
      grab.dist = Math.max(grab.dist, Math.hypot(e.clientX - grab.start.x, e.clientY - grab.start.y));
      grab.y = clamp(grab.y + dx * GRAB_RATE, -GRAB_YAW, GRAB_YAW);
      grab.x = clamp(grab.x + dy * GRAB_RATE, -GRAB_TILT, GRAB_TILT);
      grab.flick = { x: dy * GRAB_RATE * 60, y: dx * GRAB_RATE * 60 };
      grab.moved = performance.now();
    } else {
      container.style.cursor = caseAt(pointer.x, pointer.y) ? 'pointer' : '';
    }
  };
  const onLeave = () => {
    pointer.over = false;
    dirty = true; schedule();
  };
  const onDown = (e) => {
    if (!item || e.button !== 0) return;
    const [x, y] = toNdc(e);
    if (!caseAt(x, y)) return;
    grab.active = true;
    grab.start = { x: e.clientX, y: e.clientY };
    grab.last = { x: e.clientX, y: e.clientY };
    grab.dist = 0;
    grab.flick = { x: 0, y: 0 };
    container.setPointerCapture(e.pointerId);
    container.style.cursor = 'grabbing';
  };
  const onUp = (e) => {
    if (!grab.active) return;
    grab.active = false;
    const still = performance.now() - grab.moved > 90;
    grab.vx = still ? 0 : grab.flick.x;
    grab.vy = still ? 0 : grab.flick.y;
    if (container.hasPointerCapture(e.pointerId)) container.releasePointerCapture(e.pointerId);
    container.style.cursor = '';
    if (e.type === 'pointerup' && grab.dist < TAP_SLOP) toggleOpen();
  };
  container.addEventListener('pointermove', onMove);
  container.addEventListener('pointerleave', onLeave);
  container.addEventListener('pointerdown', onDown);
  container.addEventListener('pointerup', onUp);
  container.addEventListener('pointercancel', onUp);

  function wantsFrames() {
    return !!(getSpin() || Math.abs(st.spinRate) > 0.004 || artMix < 1 ||
      st.phase === 'opening' || st.phase === 'closing' || grab.active ||
      Math.abs(grab.x) + Math.abs(grab.y) + Math.abs(grab.vx) + Math.abs(grab.vy) > 0.001 ||
      Math.abs(lean.x - (Number(control.tiltX) || 0) * (grid ? 0.19 : 0.42)) +
      Math.abs(lean.y - (Number(control.tiltY) || 0) * (grid ? 0.27 : 0.75)) > 0.001);
  }
  function schedule() {
    if (disposed || failed || !item || !control.active || document.hidden || raf) return;
    raf = requestAnimationFrame(tick);
  }
  function tick(now) {
    raf = 0;
    if (disposed || failed || !control.active || document.hidden || !item) { last = 0; return; }
    const gap = last ? (now - last) / 1000 : 1 / targetFPS;
    if (last && gap < 1 / targetFPS - 0.001) { schedule(); return; }
    last = now;
    frame(Math.min(gap, 1 / 15));
    dirty = false;
    if (wantsFrames()) schedule();
    else last = 0;
  }
  function visibility() {
    if (document.hidden || !control.active) { cancelAnimationFrame(raf); raf = 0; last = 0; }
    else { dirty = true; schedule(); }
  }
  document.addEventListener('visibilitychange', visibility);

  function fallbackArt() {
    const c = document.createElement('canvas'); c.width = c.height = 512;
    const g = c.getContext('2d');
    const fill = g.createLinearGradient(0, 0, 512, 512);
    fill.addColorStop(0, '#e8e6f7'); fill.addColorStop(0.38, '#626baf'); fill.addColorStop(1, '#19233f');
    g.fillStyle = fill; g.fillRect(0, 0, 512, 512);
    g.strokeStyle = 'rgba(255,255,255,.13)'; g.lineWidth = 1;
    for (let r = 84; r < 360; r += 13) { g.beginPath(); g.arc(256,256,r,0,Math.PI*2); g.stroke(); }
    g.fillStyle='rgba(255,255,255,.88)'; g.font='500 35px system-ui'; g.textAlign='center';
    g.fillText('M U S I C',256,156); g.font='13px system-ui'; g.fillText('OFFLINE COLLECTION',256,384);
    return c.toDataURL('image/png');
  }
  const defaultArt = fallbackArt();
  async function updateArt(art) {
    const key = typeof art === 'string' && /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(art) && art.length <= 8 * 1024 * 1024 ? art : defaultArt;
    if (key === artKey) return;
    artKey = key; artLoading = true;
    const generation = ++artGeneration;
    let tex;
    try { tex = await new THREE.TextureLoader().loadAsync(key); }
    catch { try { tex = await new THREE.TextureLoader().loadAsync(defaultArt); } catch { fatal('texture-unavailable'); return; } }
    if (disposed || failed || generation !== artGeneration) { tex.dispose(); return; }
    artLoading = false; artworkCompletedAt = performance.now();
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
    if (!item) {
      currentArt = previousArt = tex;
      item = buildCase(tex);
      if (control.open) toggleOpen(true);
    } else {
      if (previousArt && previousArt !== currentArt) previousArt.dispose();
      previousArt = currentArt;
      currentArt = tex;
      artMix = control.still || control.reducedMotion || firstFrame ? 1 : 0;
      const u = item.discMesh.material.uniforms;
      u.uArt.value = currentArt; u.uArtPrevious.value = previousArt; u.uArtMix.value = artMix;
      if (artMix === 1) { previousArt.dispose(); previousArt = currentArt; u.uArtPrevious.value = currentArt; }
    }
    dirty = true;
    layout();
    schedule();
  }
  function update(state) {
    if (disposed || failed) return;
    const openBefore = control.open;
    const motionBefore = control.reducedMotion;
    const changedEpoch = typeof state.epoch === 'string' && state.epoch !== control.epoch;
    Object.assign(control, state);
    if (changedEpoch) {
      firstFrame = true; announcedFrame = '';
      st.phase = 'rest'; st.phaseAt = st.t; st.open = false; st.closeAfter = false;
      st.auto = false; st.spinRate = 0;
      lean.x = lean.y = grab.x = grab.y = grab.vx = grab.vy = 0;
    }
    if (Array.isArray(control.background) && control.background.length === 3) {
      const linear = control.background.map(v => {
        v = clamp(Number(v) || 0, 0, 1); return v < 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
      });
      background.set(...linear);
    }
    if (control.reducedMotion) st.spinRate = 0;
    if (state.animateTilt === false) {
      lean.x = (Number(control.tiltX) || 0) * (grid ? 0.19 : 0.42);
      lean.y = (Number(control.tiltY) || 0) * (grid ? 0.27 : 0.75);
      grab.x = grab.y = grab.vx = grab.vy = 0;
    }
    if (changedEpoch || openBefore !== control.open || (!motionBefore && control.reducedMotion)) toggleOpen(!!control.open);
    updateArt(control.art);
    dirty = true;
    visibility();
  }
  update(control);
  layout();

  return {
    update,
    still: () => {
      if(firstFrame || artLoading || artMix<1 || failed || disposed) return null;
      // Draw synchronously before reading the WebGL buffer; no preserved buffer or timer.
      const pose=showPose(0); pose.yaw=-.2;pose.pitch=-.12;pose.roll=.03;pose.y=0;
      place(pose);fitPoseInsideArtwork();draw();
      return canvas.toDataURL('image/png').split(',')[1];
    },
    setOpen: (on) => { control.open = !!on; toggleOpen(on); },
    debug: () => ({ hingeAxis: cassette ? 'x' : 'y', hingeEdge: cassette ? 'bottom' : 'left', lidAngle: item ? showPose(st.t).lid : 0, medium: cassette ? 'cassette' : 'cd', reelCount: item?.reels.length || 0, reelSpin: cassette ? st.spin*3 : 0, quality: grid ? 'grid' : 'hero', roomSize: ROOM_SIZE, pixelRatio: renderer.getPixelRatio(),
      msaaSamples: sampleCount, refractionSamples: samples, fittedExtent, fitRatio, firstFrameMs, artworkCompletedAt,
      epoch: control.epoch, artToken: control.artToken, artLoading,
      fpsLimit: targetFPS, playing: !!control.playing, reducedMotion: !!control.reducedMotion, frameCount, active: !!control.active, scheduled: !!raf, disposed, ready: !firstFrame,
      entranceSpeed: Number(control.entranceSpeed) || 1, openingDuration: OPEN_T / (Number(control.entranceSpeed) || 1),
      open: st.open, phase: st.phase, spin: st.spin, tiltX:lean.x, tiltY:lean.y, artMix, textureCount: renderer.info.memory.textures,
      geometryCount: renderer.info.memory.geometries, width: rtPage.width, height: rtPage.height }),
    dispose() {
      if (disposed) return;
      disposed = true;
      cancelAnimationFrame(raf);
      ro.disconnect();
      canvas.removeEventListener('webglcontextlost', contextLost);
      document.removeEventListener('visibilitychange', visibility);
      artGeneration++;
      if (previousArt && previousArt !== currentArt) previousArt.dispose();
      currentArt?.dispose();
      container.removeEventListener('pointermove', onMove);
      container.removeEventListener('pointerleave', onLeave);
      container.removeEventListener('pointerdown', onDown);
      container.removeEventListener('pointerup', onUp);
      container.removeEventListener('pointercancel', onUp);
      for (const d of disposables) d.dispose();
      for (const r of [rtPage, ...rt, rtBright, rtStarA, rtStarB, roomRT]) r.dispose();
      renderer.dispose();
      renderer.forceContextLoss();
      canvas.remove();
    },
  };
}

