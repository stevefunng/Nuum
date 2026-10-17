import type { NunuPose } from "./nunu-animation";

// Coordinates are authored against the 1254px plush original. A dense mesh keeps
// the fur attached to the same surface while shoulders, eyes and feet articulate.
const VERTEX = `
attribute vec2 a_uv;
varying vec2 v_uv;
uniform vec4 u_body; // left arm, right arm, head, bob
uniform vec4 u_face; // gaze x/y, blink, smile
uniform vec2 u_feet;
uniform vec3 u_shape;
vec2 rotateAt(vec2 p, vec2 pivot, float angle) {
  float c = cos(angle), s = sin(angle);
  vec2 d = p - pivot;
  return pivot + vec2(c*d.x-s*d.y, s*d.x+c*d.y);
}
float patch(vec2 p, vec2 center, vec2 inner, vec2 outer) {
  vec2 distance = abs(p - center);
  vec2 weight = 1.0 - smoothstep(inner, outer, distance);
  return weight.x * weight.y;
}
void main() {
  v_uv = a_uv;
  vec2 source = a_uv * 1254.0;
  vec2 p = source;
  float leftEye = patch(source, vec2(498.0, 633.0), vec2(38.0, 38.0), vec2(72.0, 72.0));
  float rightEye = patch(source, vec2(795.0, 633.0), vec2(38.0, 38.0), vec2(72.0, 72.0));
  float eyes = max(leftEye, rightEye);
  p += u_face.xy * eyes;
  p.y += (633.0-source.y) * u_face.z * eyes;
  float mouth = patch(source, vec2(642.0, 674.0), vec2(36.0, 18.0), vec2(65.0, 45.0));
  p.y += (source.y-670.0) * u_face.w * mouth;
  // One connected surface: shoulder weights reach zero inside the torso, so
  // no separated textures, hard cut edges or reconstructed fur are needed.
  float armsY = smoothstep(645.0, 745.0, source.y) * (1.0-smoothstep(900.0, 995.0, source.y));
  float leftArm = (1.0-smoothstep(190.0, 345.0, source.x)) * armsY;
  float rightArm = smoothstep(925.0, 1085.0, source.x) * armsY;
  p += (rotateAt(source, vec2(290.0, 740.0), u_body.x*.65)-source) * leftArm;
  p += (rotateAt(source, vec2(975.0, 740.0), u_body.y*.65)-source) * rightArm;
  float upper = 1.0-smoothstep(830.0, 1120.0, source.y);
  p = mix(p, rotateAt(p, vec2(627.0, 950.0), u_body.z), upper);
  float leftFoot = patch(source, vec2(465.0, 1115.0), vec2(80.0, 30.0), vec2(135.0, 80.0));
  float rightFoot = patch(source, vec2(790.0, 1115.0), vec2(80.0, 30.0), vec2(135.0, 80.0));
  p += (rotateAt(source, vec2(465.0, 1085.0), u_feet.x)-source) * leftFoot;
  p += (rotateAt(source, vec2(790.0, 1085.0), u_feet.y)-source) * rightFoot;
  p.y += u_body.w;
  float width = mix(u_shape.x, u_shape.y, smoothstep(200.0, 1000.0, source.y));
  p.x = 627.0 + (p.x-627.0)*width;
  p.y = 627.0 + (p.y-627.0)*u_shape.z;
  gl_Position = vec4((p/1254.0*2.0-1.0) * vec2(1.0, -1.0), 0.0, 1.0);
}`;
const FRAGMENT = `
precision highp float;
varying vec2 v_uv;
uniform sampler2D u_image;
uniform vec3 u_pigment;
void main() {
  vec4 sampleColor = texture2D(u_image, v_uv);
  vec3 straight = sampleColor.rgb / max(sampleColor.a, .001);
  float light = dot(straight, vec3(.2126, .7152, .0722));
  vec3 tint = mix(u_pigment, vec3(1.0), smoothstep(.8, 1.0, light));
  gl_FragColor = vec4(straight * tint * sampleColor.a, sampleColor.a);
}
`;

export interface NunuRig {
  resize(): void;
  draw(pose: NunuPose): void;
  dispose(): void;
}

export function createNunuRig(canvas: HTMLCanvasElement, image: HTMLImageElement, shape: readonly [number, number, number], pigment: number[]): NunuRig {
  const gl = canvas.getContext("webgl", { alpha: true, premultipliedAlpha: true });
  if (!gl) throw new Error("Nunu mesh rendering is unavailable");
  const shaders: WebGLShader[] = [];
  const compile = (kind: number, text: string) => {
    const shader = gl.createShader(kind)!;
    shaders.push(shader);
    gl.shaderSource(shader, text);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const reason = gl.getShaderInfoLog(shader);
      shaders.forEach(item => gl.deleteShader(item));
      throw new Error(reason ?? "Nunu shader compilation failed");
    }
    return shader;
  };
  const program = gl.createProgram()!;
  gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    shaders.forEach(item => gl.deleteShader(item));
    gl.deleteProgram(program);
    throw new Error("Nunu shader linking failed");
  }
  gl.useProgram(program);
  const segments = 128;
  const vertices = new Float32Array((segments+1)**2 * 2);
  const indices = new Uint16Array(segments**2 * 6);
  let index = 0;
  for (let y = 0; y <= segments; y++) for (let x = 0; x <= segments; x++) {
    const vertex = y*(segments+1)+x;
    vertices[vertex*2] = x/segments;
    vertices[vertex*2+1] = y/segments;
    if (x < segments && y < segments) {
      const below = vertex+segments+1;
      indices.set([vertex, vertex+1, below, vertex+1, below+1, below], index);
      index += 6;
    }
  }
  const vertexBuffer = gl.createBuffer()!;
  gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, vertices, gl.STATIC_DRAW);
  const uv = gl.getAttribLocation(program, "a_uv");
  gl.enableVertexAttribArray(uv);
  gl.vertexAttribPointer(uv, 2, gl.FLOAT, false, 0, 0);
  const indexBuffer = gl.createBuffer()!;
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
  const texture = gl.createTexture()!;
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
  // Upload the original at native resolution. NPOT texture: no intermediary
  // canvas upscale or trilinear mip blending that softens fine material detail.
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.uniform3fv(gl.getUniformLocation(program, "u_shape"), shape);
  gl.uniform3fv(gl.getUniformLocation(program, "u_pigment"), pigment);
  gl.enable(gl.BLEND);
  gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  const body = gl.getUniformLocation(program, "u_body");
  const face = gl.getUniformLocation(program, "u_face");
  const feet = gl.getUniformLocation(program, "u_feet");
  return {
    resize() {
      const size = Math.max(1, Math.round(canvas.clientWidth * Math.max(2, window.devicePixelRatio || 1)));
      if (canvas.width !== size || canvas.height !== size) canvas.width = canvas.height = size;
      gl.viewport(0, 0, size, size);
    },
    draw(pose) {
      gl.uniform4f(body, pose.leftArm, pose.rightArm, pose.head, pose.bob);
      gl.uniform4f(face, pose.gazeX, pose.gazeY, pose.blink, pose.smile);
      gl.uniform2f(feet, pose.leftFoot, pose.rightFoot);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawElements(gl.TRIANGLES, indices.length, gl.UNSIGNED_SHORT, 0);
    },
    dispose() {
      gl.deleteBuffer(vertexBuffer);
      gl.deleteBuffer(indexBuffer);
      gl.deleteTexture(texture);
      gl.deleteProgram(program);
      shaders.forEach(shader => gl.deleteShader(shader));
    },
  };
}
