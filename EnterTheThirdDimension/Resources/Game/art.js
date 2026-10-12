/*
 * Enter the Third Dimension — original pixel character art.
 *
 * The palette and courier silhouette continue our original Moonhop character:
 * amber hood, teal travelling coat, coral scarf, small satchel and sturdy boots.
 * Every visible cell is one fully opaque logical pixel. A dot is transparent.
 * The renderer may extrude these same cells; no raster image or outside asset
 * is loaded, and NPC thickness belongs to scene geometry, not to this file.
 *
 * Public contract:
 *   TD_ART.sprites.hero[0..3] = walking cycle; frame 0 also serves as idle.
 *   TD_ART.sprites.hero[4]    = jump, with tucked boots and a lifted scarf.
 *   TD_ART.sprites.sage[0], child[0], fox[0] = distinct flat-world characters.
 *   Each frame is { rows: string[], palette: { character: '#rrggbb' }, width,
 *                   height }. Faces point right and can be mirrored by the
 *                   renderer. Sprite origins are top left; align the feet.
 */
(function () {
  'use strict';

  function grid(width, height) {
    return Array.from({ length: height }, function () {
      return Array(width).fill('.');
    });
  }

  function fill(pixels, x, y, width, height, color) {
    for (var row = Math.max(0, y); row < Math.min(pixels.length, y + height); row++) {
      for (var col = Math.max(0, x); col < Math.min(pixels[0].length, x + width); col++) {
        pixels[row][col] = color;
      }
    }
  }

  function bands(pixels, lines, color) {
    lines.forEach(function (line) {
      fill(pixels, line[1], line[0], line[2], 1, color);
    });
  }

  function frame(pixels, palette) {
    return {
      rows: pixels.map(function (row) { return row.join(''); }),
      palette: palette,
      width: pixels[0].length,
      height: pixels.length
    };
  }

  var courierPalette = {
    o: '#183640', // Blue-black contours, shared by the original courier.
    H: '#DCA56F', // Amber wool.
    L: '#F7D295', // Hood and satchel highlights.
    h: '#AD7858', // Warm folds beneath the hood.
    F: '#FFDFB5', // Face and hands.
    f: '#EABA93',
    r: '#D58F7D',
    T: '#79B8AA', // Teal coat.
    t: '#559597',
    U: '#376878',
    Q: '#C5DEBC', // Small reflected moonlight accents.
    C: '#E8897F', // Coral scarf.
    c: '#B85E69',
    B: '#8D674D', // Leather strap.
    b: '#B98A5E',
    S: '#87918A', // Worn boot toes.
    G: '#EECB80'
  };

  var courierPoses = [
    { bob: 0, scarf: 0, backArm: 0, frontArm: 0,
      legs: [[8, 22, 28, -1], [15, 22, 28, 0]] },
    { bob: 0, scarf: -1, backArm: 1, frontArm: -1,
      legs: [[6, 22, 26, -2], [17, 22, 28, 0]] },
    { bob: -1, scarf: 0, backArm: 0, frontArm: 0,
      legs: [[12, 22, 26, 1], [10, 22, 28, 0]] },
    { bob: 0, scarf: 1, backArm: -1, frontArm: 1,
      legs: [[17, 22, 27, 0], [7, 22, 28, -2]] },
    { bob: -1, scarf: -3, backArm: -1, frontArm: -2,
      legs: [[8, 21, 25, -3], [15, 22, 26, 1]] }
  ];

  function courier(pose) {
    var pixels = grid(24, 30);
    var r = function (x, y, w, h, color) {
      fill(pixels, x, y + pose.bob, w, h, color);
    };

    // Separate trouser legs keep the gait readable when the pixels gain volume.
    pose.legs.forEach(function (leg, index) {
      var x = leg[0], top = leg[1], boot = leg[2], toe = leg[3];
      fill(pixels, x, top, 4, boot - top + 1, 'o');
      fill(pixels, x + 1, top + 1, 2, Math.max(1, boot - top - 1), index ? 't' : 'U');
      fill(pixels, x + toe, boot, 6, 2, 'o');
      fill(pixels, x + toe + 1, boot, 4, 1, 'S');
    });

    // Scarf tail sits behind the coat and flutters through the five poses.
    r(0, 14 + pose.scarf, 5, 2, 'c');
    r(1, 13 + pose.scarf, 6, 2, 'C');
    r(0, 15 + pose.scarf, 3, 1, 'c');
    r(4, 14, 5, 2, 'C');

    // The little travel satchel is part of the courier's asymmetric silhouette.
    r(3, 15 + pose.backArm, 6, 7, 'o');
    r(4, 15 + pose.backArm, 4, 6, 'b');
    r(4, 16 + pose.backArm, 2, 4, 'H');
    r(5, 15 + pose.backArm, 2, 1, 'L');
    r(4, 20 + pose.backArm, 4, 1, 'B');
    r(6, 18 + pose.backArm, 1, 1, 'G');

    // A slightly tapered coat, a split hem, and a diagonal satchel strap.
    r(7, 13, 11, 2, 'o');
    r(6, 15, 13, 7, 'o');
    r(7, 21, 12, 3, 'o');
    r(7, 15, 11, 6, 'T');
    r(8, 21, 10, 2, 'U');
    r(8, 15, 3, 4, 'Q');
    r(9, 16, 3, 5, 'T');
    r(15, 16, 3, 6, 't');
    r(12, 21, 1, 3, 'o');
    r(8, 14, 2, 2, 'B');
    r(9, 16, 2, 2, 'B');
    r(10, 18, 2, 1, 'B');
    r(11, 19, 2, 1, 'B');
    r(12, 20, 2, 1, 'G');
    r(15, 18, 1, 1, 'Q');

    // The leading arm swings independently of the satchel.
    r(18, 15 + pose.frontArm, 3, 6, 'o');
    r(18, 16 + pose.frontArm, 2, 3, 't');
    r(19, 19 + pose.frontArm, 2, 2, 'F');
    r(19, 20 + pose.frontArm, 1, 1, 'f');

    // Hand-shaped hood outline: rounded crown, low back, protruding nose.
    [
      [1, 8, 9], [2, 6, 13], [3, 5, 15], [4, 5, 16],
      [5, 4, 17], [6, 4, 17], [7, 4, 17], [8, 4, 17],
      [9, 5, 18], [10, 5, 16], [11, 6, 14], [12, 8, 10]
    ].forEach(function (line) { r(line[1], line[0], line[2], 1, 'o'); });
    r(8, 2, 9, 1, 'L');
    r(6, 3, 12, 2, 'H');
    r(7, 3, 7, 1, 'L');
    r(6, 4, 4, 2, 'L');
    r(5, 5, 14, 4, 'H');
    r(6, 9, 7, 2, 'h');
    r(5, 7, 2, 2, 'h');
    r(9, 5, 3, 2, 'h');
    r(10, 7, 2, 3, 'h');

    // One attentive eye and a softly stepped cheek keep the face legible at 1x.
    r(12, 5, 7, 1, 'f');
    r(11, 6, 9, 3, 'F');
    r(12, 9, 9, 1, 'F');
    r(20, 9, 2, 1, 'F');
    r(13, 10, 7, 1, 'F');
    r(14, 11, 5, 1, 'f');
    r(11, 6, 2, 1, 'f');
    r(17, 7, 1, 2, 'o');
    r(18, 9, 1, 1, 'r');
    r(18, 10, 2, 1, 'f');

    // Wrap the scarf over the collar, then add its small folded knot.
    r(7, 12, 11, 3, 'c');
    r(6, 12, 12, 2, 'C');
    r(7, 12, 5, 1, 'F');
    r(6, 14, 3, 2, 'C');
    r(7, 15, 2, 1, 'c');
    return frame(pixels, courierPalette);
  }

  var sagePalette = {
    o: '#263343', P: '#51475F', p: '#766887', L: '#A697B2',
    B: '#4D747F', b: '#78A7A5', F: '#E8C3A4', f: '#C89E87',
    W: '#E4E4D8', w: '#AFBFC0', G: '#D9C393',
    S: '#8F745C', s: '#C2A17A', A: '#8FD9CD', a: '#D3F4D6'
  };

  function sage() {
    var pixels = grid(28, 36);
    var r = function (x, y, w, h, color) { fill(pixels, x, y, w, h, color); };

    // A narrow walking staff and mint crystal make a tall, recognisable contour.
    r(24, 4, 3, 31, 'o');
    r(25, 5, 1, 29, 'S');
    r(24, 2, 3, 5, 'o');
    r(23, 3, 5, 3, 'o');
    r(24, 3, 3, 3, 'A');
    r(25, 2, 1, 3, 'a');
    r(25, 8, 1, 3, 's');

    // Broad, layered robe below a small face; this is no recoloured courier.
    bands(pixels, [[15, 7, 11], [16, 5, 15], [17, 5, 15], [18, 4, 17],
      [19, 4, 17], [20, 4, 17], [21, 4, 17], [22, 3, 19], [23, 3, 19],
      [24, 3, 19], [25, 3, 19], [26, 3, 19], [27, 2, 21], [28, 2, 21],
      [29, 2, 21], [30, 2, 21], [31, 2, 21], [32, 2, 21], [33, 3, 19]], 'o');
    r(6, 17, 13, 7, 'P');
    r(5, 23, 15, 5, 'P');
    r(4, 28, 17, 5, 'P');
    r(6, 18, 4, 8, 'B');
    r(5, 26, 4, 6, 'B');
    r(7, 19, 2, 5, 'b');
    r(14, 20, 3, 12, 'p');
    r(16, 26, 2, 7, 'L');
    r(4, 32, 17, 1, 'G');
    r(6, 34, 5, 2, 'o');
    r(15, 34, 6, 2, 'o');
    r(7, 34, 3, 1, 'S');
    r(17, 34, 3, 1, 'S');
    r(19, 18, 6, 4, 'o');
    r(20, 19, 4, 2, 'p');
    r(23, 19, 3, 2, 'F');

    // White hair, two gentle eyes, and a long stepped beard.
    r(6, 8, 13, 7, 'o');
    r(7, 8, 11, 7, 'w');
    r(8, 9, 10, 5, 'F');
    r(6, 10, 2, 4, 'W');
    r(18, 10, 2, 4, 'W');
    r(9, 10, 3, 1, 'W');
    r(14, 10, 3, 1, 'W');
    r(10, 11, 1, 1, 'o');
    r(15, 11, 1, 1, 'o');
    r(12, 12, 2, 2, 'f');
    bands(pixels, [[13, 7, 12], [14, 8, 11], [15, 8, 10],
      [16, 9, 9], [17, 10, 7], [18, 11, 5], [19, 12, 3]], 'W');
    r(8, 14, 2, 2, 'w');
    r(10, 16, 1, 2, 'w');
    r(15, 15, 2, 2, 'w');
    r(12, 14, 3, 1, 'f');

    // A bent, star-pinned hat with an uneven brim.
    bands(pixels, [[0, 8, 3], [1, 7, 6], [2, 6, 9], [3, 5, 12],
      [4, 5, 13], [5, 4, 15], [6, 3, 17], [7, 2, 20], [8, 4, 17]], 'o');
    bands(pixels, [[1, 8, 3], [2, 7, 6], [3, 6, 9], [4, 6, 11],
      [5, 5, 13]], 'P');
    r(8, 2, 2, 2, 'p');
    r(7, 4, 3, 2, 'p');
    r(4, 6, 15, 1, 'B');
    r(3, 7, 17, 1, 'p');
    r(5, 7, 9, 1, 'L');
    r(15, 4, 1, 3, 'G');
    r(14, 5, 3, 1, 'G');
    return frame(pixels, sagePalette);
  }

  var childPalette = {
    o: '#353447', H: '#655063', h: '#967181', L: '#B69498',
    F: '#F4D0B3', f: '#DEA78E', C: '#DF99B1', c: '#B66F94',
    P: '#F2C4D3', B: '#796B99', b: '#ADA2C5',
    A: '#85C9C0', G: '#F0CE86', S: '#B29471'
  };

  function child() {
    var pixels = grid(21, 25);
    var r = function (x, y, w, h, color) { fill(pixels, x, y, w, h, color); };

    r(6, 19, 4, 5, 'o');
    r(12, 19, 4, 5, 'o');
    r(7, 20, 2, 3, 'b');
    r(13, 20, 2, 3, 'b');
    r(5, 23, 5, 2, 'o');
    r(12, 23, 5, 2, 'o');
    r(6, 23, 3, 1, 'S');
    r(13, 23, 3, 1, 'S');

    // A rosy bell-shaped coat and one raised hand.
    bands(pixels, [[11, 7, 8], [12, 5, 12], [13, 5, 12], [14, 5, 12],
      [15, 5, 12], [16, 4, 14], [17, 4, 14], [18, 4, 14], [19, 5, 12]], 'o');
    r(6, 13, 10, 4, 'C');
    r(5, 17, 12, 2, 'c');
    r(7, 13, 3, 4, 'P');
    r(10, 14, 2, 5, 'c');
    r(11, 14, 1, 1, 'G');
    r(11, 17, 1, 1, 'G');
    r(3, 13, 3, 5, 'o');
    r(4, 14, 2, 3, 'C');
    r(4, 17, 2, 2, 'F');
    r(16, 11, 3, 5, 'o');
    r(17, 12, 2, 2, 'C');
    r(17, 10, 3, 3, 'o');
    r(18, 10, 2, 2, 'F');
    r(18, 9, 1, 2, 'F');

    // Round cheeks beneath a dark, asymmetric bob, with a little mint bow.
    bands(pixels, [[1, 7, 7], [2, 5, 11], [3, 4, 13], [4, 3, 15],
      [5, 3, 15], [6, 3, 15], [7, 4, 14], [8, 4, 14], [9, 4, 13],
      [10, 5, 11], [11, 7, 8]], 'o');
    r(6, 2, 9, 3, 'H');
    r(4, 4, 12, 4, 'H');
    r(5, 3, 4, 2, 'h');
    r(5, 4, 2, 1, 'L');
    r(5, 6, 2, 4, 'H');
    r(15, 5, 2, 5, 'H');
    r(7, 5, 8, 5, 'F');
    r(8, 10, 6, 1, 'f');
    r(7, 5, 4, 1, 'H');
    r(8, 6, 1, 1, 'h');
    r(9, 7, 1, 2, 'o');
    r(13, 7, 1, 2, 'o');
    r(7, 9, 2, 1, 'f');
    r(14, 9, 1, 1, 'f');
    r(11, 10, 1, 1, 'C');
    r(3, 1, 3, 3, 'o');
    r(3, 1, 2, 2, 'A');
    r(5, 2, 2, 2, 'A');
    r(5, 2, 1, 1, 'G');
    r(8, 12, 6, 1, 'A');
    return frame(pixels, childPalette);
  }

  var foxPalette = {
    o: '#493A42', R: '#BE704F', r: '#925449', H: '#EAA16A',
    L: '#FFD09A', W: '#EEE0C1', w: '#C5BAA7', E: '#253A43'
  };

  function fox() {
    var pixels = grid(30, 18);
    var r = function (x, y, w, h, color) { fill(pixels, x, y, w, h, color); };

    // An upward-curled cream-tipped tail, long body and triangular ears.
    bands(pixels, [[4, 0, 4], [5, 0, 6], [6, 1, 7], [7, 2, 7],
      [8, 3, 9], [9, 4, 12], [10, 5, 14], [11, 7, 13]], 'o');
    r(1, 5, 3, 2, 'W');
    r(3, 6, 4, 2, 'W');
    r(5, 8, 5, 2, 'H');
    r(8, 10, 8, 1, 'R');
    r(10, 8, 14, 7, 'o');
    r(11, 9, 12, 4, 'R');
    r(12, 9, 9, 2, 'H');
    r(16, 12, 7, 2, 'W');
    r(11, 14, 4, 4, 'o');
    r(20, 14, 4, 4, 'o');
    r(12, 14, 2, 2, 'r');
    r(21, 14, 2, 2, 'W');

    bands(pixels, [[0, 19, 2], [1, 18, 4], [2, 18, 5], [3, 18, 6],
      [4, 17, 10], [5, 17, 11], [6, 18, 10], [7, 18, 10],
      [8, 19, 11], [9, 19, 10], [10, 20, 7], [11, 21, 4]], 'o');
    r(19, 2, 2, 4, 'R');
    r(20, 3, 1, 2, 'r');
    r(24, 1, 2, 4, 'o');
    r(24, 3, 1, 2, 'H');
    r(18, 5, 9, 2, 'H');
    r(20, 7, 7, 2, 'H');
    r(21, 9, 6, 1, 'W');
    r(22, 10, 3, 1, 'W');
    r(26, 8, 2, 1, 'W');
    r(28, 8, 2, 1, 'E');
    r(24, 6, 1, 2, 'E');
    r(20, 5, 2, 1, 'L');
    return frame(pixels, foxPalette);
  }

  window.TD_ART = {
    sprites: {
      hero: courierPoses.map(courier),
      sage: [sage()],
      child: [child()],
      fox: [fox()]
    },
    animation: {
      hero: { idle: 0, walk: [0, 1, 2, 3], jump: 4, framesPerSecond: 9 }
    },
    metadata: {
      pixelSize: 1,
      transparent: '.',
      defaultFacing: 'right',
      origin: 'top-left',
      heroCollider: { width: 16, height: 26 },
      description: 'Original Moonhop courier and flat-world neighbours'
    }
  };
})();
