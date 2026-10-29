import { sampleUnboxing } from "./nunu-unboxing-motion";

type V = [number, number, number];
type Face = { points: V[]; color: V; ribbon?: boolean };
const PAPER: V = [235, 226, 208];
const LINING: V = [248, 242, 229];
const RIBBON: V = [151, 171, 142];
const pitch = .28, yaw = -.12;
function camera([x, y, z]: V): V {
  const u = x * Math.cos(yaw) + z * Math.sin(yaw);
  const v = z * Math.cos(yaw) - x * Math.sin(yaw);
  return [u, y * Math.cos(pitch) - v * Math.sin(pitch), v * Math.cos(pitch) + y * Math.sin(pitch)];
}
function prism(faces: Face[], min: V, max: V, transform: (p: V) => V, color = PAPER) {
  const [x, y, z] = min, [X, Y, Z] = max;
  const points: V[] = [[x,y,z],[X,y,z],[X,Y,z],[x,Y,z],[x,y,Z],[X,y,Z],[X,Y,Z],[x,Y,Z]];
  for (const indices of [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]) {
    faces.push({ points: indices.map(i => transform(points[i]!)), color });
  }
}
function shell(faces: Face[], side: number, angle: number) {
  const firstFace = faces.length;
  const transform = ([x,y,z]: V): V => [side * (73 + (x - 73) * Math.cos(angle) + y * Math.sin(angle)), y * Math.cos(angle) - (x - 73) * Math.sin(angle) + 3, z];
  // Each half is a rigid, lined shell. The bottom outside edge is its hinge.
  prism(faces, [0,0,-48], [73,160,-45], transform);
  prism(faces, [0,0,45], [73,160,48], transform);
  prism(faces, [70,0,-45], [73,160,45], transform);
  prism(faces, [0,157,-48], [73,161,48], transform, LINING);
  // Folded satin strips belong to the lid, not a band tying the two halves shut.
  prism(faces, [0,161,-8], [73,161.6,8], transform, RIBBON);
  prism(faces, [73,0,-8], [73.5,160,8], transform, RIBBON);
  // Swept ribbon loop: continuous curved surface with a softly rolled cross-section.
  const point = (t: number, v: number): V => transform([
    7 + 48 * Math.sin(Math.PI * t),
    162 + 23 * Math.sin(Math.PI * t) ** .8 + 6 * Math.sin(2 * Math.PI * t) + 1.2 * Math.cos(v * Math.PI),
    v * 7 + 3 * Math.sin(Math.PI * t),
  ]);
  for (let i = 0; i < 36; i++) for (let j = 0; j < 4; j++) {
    const a = i / 36, b = (i + 1) / 36, v = j / 2 - 1, w = (j + 1) / 2 - 1;
    faces.push({ points: [point(a,v),point(b,v),point(b,w),point(a,w)], color: RIBBON, ribbon: true });
  }
  if (side < 0) for (let i = firstFace; i < faces.length; i++) faces[i]!.points.reverse();
}

/** Small orthographic solid renderer. One camera, face lighting and depth order
 * for the packaging and the existing textured character; no CSS 3D layers. */
export function drawUnboxing(ctx: CanvasRenderingContext2D, width: number, height: number, time: number, portrait: CanvasImageSource) {
  const state = sampleUnboxing(time);
  const scale = Math.min(width / 390, height / 280) * state.zoom;
  const origin: [number, number] = [width / 2, height * .79];
  const project = (p: V): [number, number] => {
    const q = camera(p);
    return [origin[0] + q[0] * scale, origin[1] - q[1] * scale];
  };
  ctx.clearRect(0, 0, width, height);
  const shadow = (x: number, z: number, rx: number, ry: number, alpha: number) => {
    const p = project([x,0,z]);
    ctx.save(); ctx.translate(...p); ctx.scale(rx * scale, ry * scale);
    const g = ctx.createRadialGradient(0,0,0,0,0,1);
    g.addColorStop(0, `rgba(48,38,24,${alpha})`); g.addColorStop(.45, `rgba(48,38,24,${alpha * .5})`); g.addColorStop(1,"rgba(48,38,24,0)");
    ctx.fillStyle = g; ctx.fillRect(-1,-1,2,2); ctx.restore();
  };
  shadow(0,0,76,17,.23);
  for (const [side, angle] of [[-1,state.left],[1,state.right]]) {
    shadow(side * (73 + 65 * Math.sin(angle)),0,40 + 48 * Math.sin(angle),20,.15 * state.packaging);
  }
  const faces: Face[] = [];
  prism(faces, [-73,0,-48],[73,3,48], p => p, LINING);
  const baseFaces = new Set(faces);
  shell(faces,-1,state.left); shell(faces,1,state.right);
  const items: Array<{ depth: number; draw(): void }> = faces.map(face => {
    const points = face.points.map(camera);
    const a = face.points[0]!, b = face.points[1]!, c = face.points[2]!;
    const u = b.map((v,i) => v - a[i]!), v = c.map((v,i) => v - a[i]!);
    const n = [u[1]! * v[2]! - u[2]! * v[1]!, u[2]! * v[0]! - u[0]! * v[2]!, u[0]! * v[1]! - u[1]! * v[0]!];
    const length = Math.hypot(...n) || 1;
    // Two-sided ribbon; solid panel faces retain their physical normal.
    let light = (n[0]! * -.35 + n[1]! * .82 + n[2]! * .45) / length;
    if (face.ribbon) light = Math.abs(light);
    const intensity = .81 + .19 * Math.max(-.55, light);
    return {
      depth: baseFaces.has(face) ? -1000 : points.reduce((sum,p) => sum + p[2], 0) / points.length,
      draw() {
        ctx.globalAlpha = state.packaging;
        ctx.beginPath(); face.points.forEach((p,i) => { const q = project(p); if (!i) ctx.moveTo(...q); else ctx.lineTo(...q); }); ctx.closePath();
        const gradient = ctx.createLinearGradient(0, origin[1] - 160 * scale, width, origin[1]);
        const color = (extra: number) => `rgb(${face.color.map(value => Math.min(255, Math.round(value * intensity + extra))).join(" ")})`;
        gradient.addColorStop(0,color(10)); gradient.addColorStop(1,color(-3));
        ctx.fillStyle = gradient; ctx.fill();
        ctx.strokeStyle = face.ribbon ? color(0) : color(-13); ctx.lineWidth = face.ribbon ? .35 : .55 * scale; ctx.lineJoin = "round"; ctx.stroke();
        ctx.globalAlpha = 1;
      },
    };
  });
  items.push({ depth: 0, draw() {
    const foot = project([0,5,0]);
    // Source margins are preserved; the original foot baseline is at ~93%.
    ctx.drawImage(portrait, foot[0] - 89 * scale, foot[1] - 158 * scale, 178 * scale, 178 * scale);
  } });
  items.sort((a,b) => a.depth - b.depth).forEach(item => item.draw());
}
