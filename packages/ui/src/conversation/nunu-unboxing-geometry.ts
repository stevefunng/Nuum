import * as THREE from "three";

export type Point = readonly [number, number, number];
export type Surface = (u: number, v: number) => Point;

/** One indexed surface, with shared vertices so fabric and bevels shade continuously. */
export function surfaceGeometry(surface: Surface, columns = 64, rows = 24) {
  const positions: number[] = [], uv: number[] = [], indices: number[] = [];
  for (let row = 0; row <= rows; row++) {
    for (let column = 0; column <= columns; column++) {
      positions.push(...surface(column / columns, row / rows));
      uv.push(column / columns, row / rows);
      if (column < columns && row < rows) {
        const a = row * (columns + 1) + column, b = a + columns + 1;
        indices.push(a, b, a + 1, a + 1, b, b + 1);
      }
    }
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
  geometry.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  return geometry;
}

export function mesh(geometry: THREE.BufferGeometry, material: THREE.Material) {
  const object = new THREE.Mesh(geometry, material);
  object.castShadow = object.receiveShadow = true;
  return object;
}

export function roundedOutline(halfWidth: number, halfDepth: number, radius: number, t: number): [number, number] {
  const corner = Math.min(3, Math.floor(t * 4));
  const angle = (corner + (t * 4 - corner)) * Math.PI / 2;
  const centerAngle = (corner + .5) * Math.PI / 2;
  return [(halfWidth - radius) * Math.sign(Math.cos(centerAngle)) + radius * Math.cos(angle),
    (halfDepth - radius) * Math.sign(Math.sin(centerAngle)) + radius * Math.sin(angle)];
}

type Ring = readonly [halfWidth: number, halfDepth: number, radius: number, height: number];
/** A solid wall cross section: outside, rolled lip, inside, floor. */
export function vessel(rings: readonly Ring[], outer: THREE.Material, inner: THREE.Material) {
  const group = new THREE.Group();
  const profile = new THREE.CatmullRomCurve3(rings.map(ring => new THREE.Vector3(ring[0], ring[3], ring[1])), false, "catmullrom", .12);
  const radii = new THREE.CatmullRomCurve3(rings.map(ring => new THREE.Vector3(ring[2], 0, 0)), false, "catmullrom", .12);
  const rows = (rings.length - 1) * 8;
  const wall = surfaceGeometry((u, v) => {
    const p = profile.getPoint(v), radius = radii.getPoint(v).x;
    const [x, z] = roundedOutline(p.x, p.z, radius, u);
    return [x, p.y, z];
  }, 128, rows);
  const split = Math.min(rows, 33) * 128 * 6;
  wall.addGroup(0, split, 0);
  if (split < rows * 128 * 6) wall.addGroup(split, rows * 128 * 6 - split, 1);
  const walls = new THREE.Mesh(wall, [outer, inner]);
  walls.castShadow = walls.receiveShadow = true;
  group.add(walls);
  const floor = rings[rings.length - 1]!;
  const geometry = surfaceGeometry((u, v) => {
    const [x, z] = roundedOutline(floor[0], floor[1], floor[2], u);
    return [x * v, floor[3], z * v];
  }, 128, 8);
  group.add(mesh(geometry, inner));
  return group;
}

export function lid(halfWidth: number, halfDepth: number, radius: number, paper: THREE.Material, lining: THREE.Material) {
  const group = new THREE.Group();
  // Both faces are closed solids. The recessed inner pad sits inside the rolled edge.
  group.add(vessel([
    [halfWidth - .025, halfDepth - .025, radius, 0],
    [halfWidth, halfDepth, radius, .025],
    [halfWidth, halfDepth, radius, .115],
    [halfWidth - .025, halfDepth - .025, radius, .14],
    [halfWidth - .06, halfDepth - .06, radius - .02, .145],
    [halfWidth - .075, halfDepth - .075, radius - .03, .145],
  ], paper, paper));
  const pad = vessel([
    [halfWidth - .03, halfDepth - .03, radius, .005],
    [halfWidth - .055, halfDepth - .055, radius, -.015],
    [halfWidth - .10, halfDepth - .10, radius - .025, -.02],
    [halfWidth - .13, halfDepth - .13, radius - .04, .015],
    [halfWidth - .15, halfDepth - .15, radius - .05, .025],
  ], paper, lining);
  group.add(pad);
  return group;
}

/** Woven cotton: fiber relief, never a screen-space noise overlay. */
export function weaveTexture() {
  const size = 256, pixels = new Uint8Array(size * size * 4);
  let seed = 71;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    const thread = Math.cos(x * Math.PI / 2) * 17 + Math.cos(y * Math.PI / 2) * 13;
    const value = 150 + thread + (seed >>> 24) * .12;
    const index = (y * size + x) * 4;
    pixels[index] = pixels[index + 1] = pixels[index + 2] = value;
    pixels[index + 3] = 255;
  }
  const texture = new THREE.DataTexture(pixels, size, size);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(3, 2);
  texture.needsUpdate = true;
  return texture;
}

function cloth(surface: Surface, material: THREE.Material, columns = 64, rows = 12) {
  return mesh(surfaceGeometry(surface, columns, rows), material);
}

export function bow(material: THREE.Material) {
  const group = new THREE.Group();
  for (const side of [-1, 1]) {
    // The return half of each loop dips underneath the broad, domed upper fold.
    group.add(cloth((u, v) => {
      const angle = u * Math.PI * 2;
      const reach = (1 - Math.cos(angle)) * .25;
      const width = (v - .5) * .22;
      return [side * (.035 + reach), .09 + Math.sin(angle) * .115 + reach * .20 + width * Math.cos(angle) * .24,
        width + Math.sin(angle) * .065 - reach * .16];
    }, material, 96));
    group.add(cloth((u, v) => {
      const width = (v - .5) * .19;
      // A shallow fishtail cut and a curl lift the free ends off the lid.
      const end = u - Math.max(0, (u - .88) / .12) * .055 * (1 - Math.abs(v * 2 - 1));
      return [side * (.03 + end * .40) + width, .035 + .055 * Math.sin(u * Math.PI) + .018 * Math.sin(v * Math.PI), .08 + end * .48];
    }, material));
  }
  const knot = mesh(new THREE.SphereGeometry(1, 40, 24), material);
  knot.scale.set(.105, .077, .12);
  knot.rotation.z = -.17;
  knot.position.set(0, .08, .02);
  group.add(knot);
  return group;
}

export function tiedRibbon(halfWidth: number, halfDepth: number, height: number, material: THREE.Material) {
  const group = bow(material);
  group.position.y = height;
  for (const rotate of [false, true]) {
    const length = rotate ? halfWidth : halfDepth;
    const band = cloth((u, v) => {
      const distance = (u * 2 - 1) * (length + .12);
      const edge = Math.max(0, Math.abs(distance) - length + .015);
      const z = Math.sign(distance) * Math.min(length + .012, Math.abs(distance));
      const x = (v - .5) * .18;
      const y = .006 - edge + .008 * Math.sin(v * Math.PI);
      return rotate ? [z, y, x] : [x, y, z];
    }, material, 96);
    group.add(band);
  }
  return group;
}

export interface PaperPetal {
  object: THREE.Mesh;
  update(open: number): void;
}
export function paperPetal(side: number, material: THREE.Material): PaperPetal {
  const back = side === 2, front = side === 0;
  const length = back ? 2.37 : front ? 1.95 : 2.16;
  const halfWidth = side % 2 ? .69 : .94;
  const hinge = side % 2 ? .94 : .69;
  const geometry = surfaceGeometry(() => [0, 0, 0], 64, 64);
  const object = mesh(geometry, material);
  const backing = geometry.clone();
  const backMesh = mesh(backing, material);
  object.add(backMesh);
  // A narrow continuous edge closes the sheet, including the exposed curled tips.
  const boundary: number[] = [];
  for (let column = 0; column < 64; column++) boundary.push(column);
  for (let row = 0; row < 64; row++) boundary.push(row * 65 + 64);
  for (let column = 64; column > 0; column--) boundary.push(64 * 65 + column);
  for (let row = 64; row > 0; row--) boundary.push(row * 65);
  const edge = new THREE.BufferGeometry();
  const edgePositions = new THREE.Float32BufferAttribute(new Float32Array((boundary.length + 1) * 6), 3);
  const edgeIndices: number[] = [];
  for (let i = 0; i < boundary.length; i++) edgeIndices.push(i * 2, i * 2 + 1, i * 2 + 2, i * 2 + 2, i * 2 + 1, i * 2 + 3);
  edge.setAttribute("position", edgePositions);
  edge.setIndex(edgeIndices);
  object.add(mesh(edge, material));
  object.rotation.y = side * Math.PI / 2;
  const position = geometry.getAttribute("position") as THREE.BufferAttribute;
  const profile: Array<[number, number]> = [];
  return { object, update(open) {
    profile.length = 0;
    let height = .035, depth = hinge;
    for (let row = 0; row <= 64; row++) {
      const v = row / 64;
      profile.push([height, depth]);
      const closedAngle = -.045 - 1.53 * THREE.MathUtils.smoothstep(v, .43, .57);
      const finalAngle = front ? 1.53 + .10 * v : back ? -.045 + .10 * v : .34 + .25 * v;
      const angle = THREE.MathUtils.lerp(closedAngle, finalAngle, open);
      height += Math.cos(angle) * length / 64;
      depth += Math.sin(angle) * length / 64;
    }
    for (let row = 0; row <= 64; row++) for (let column = 0; column <= 64; column++) {
      const u = column / 32 - 1, v = row / 64, [y, z] = profile[row]!;
      const edge = Math.abs(u);
      const crease = Math.abs(edge - Math.max(0, (v - .38) * 1.7));
      const ridge = .040 * Math.exp(-crease * 55) * Math.sin(v * Math.PI);
      const curl = edge ** 6 * Math.sin(v * Math.PI) * .09;
      const width = halfWidth * (1 + open * .09 * v);
      position.setXYZ(row * 65 + column, u * width,
        y + curl + ridge + open * edge ** 2 * v ** 5 * .11,
        z + .04 * Math.sin(u * 2.7 + v * 7) * Math.sin(v * Math.PI) + ridge);
    }
    position.needsUpdate = true;
    geometry.computeVertexNormals();
    geometry.computeBoundingSphere();
    const normals = geometry.getAttribute("normal") as THREE.BufferAttribute;
    const backPositions = backing.getAttribute("position") as THREE.BufferAttribute;
    for (let i = 0; i < position.count; i++) {
      backPositions.setXYZ(i, position.getX(i) - normals.getX(i) * .006,
        position.getY(i) - normals.getY(i) * .006, position.getZ(i) - normals.getZ(i) * .006);
    }
    backPositions.needsUpdate = true;
    backing.computeVertexNormals();
    backing.computeBoundingSphere();
    for (let i = 0; i <= boundary.length; i++) {
      const vertex = boundary[i % boundary.length]!;
      edgePositions.setXYZ(i * 2, position.getX(vertex), position.getY(vertex), position.getZ(vertex));
      edgePositions.setXYZ(i * 2 + 1, backPositions.getX(vertex), backPositions.getY(vertex), backPositions.getZ(vertex));
    }
    edgePositions.needsUpdate = true;
    edge.computeVertexNormals();
    edge.computeBoundingSphere();
  } };
}
