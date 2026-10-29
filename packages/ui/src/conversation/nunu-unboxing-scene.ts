import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { lid, mesh, paperPetal, tiedRibbon, vessel, weaveTexture, type PaperPetal } from "./nunu-unboxing-geometry";
import { sampleUnboxing, type UnboxingPackage } from "./nunu-unboxing-motion";

export interface UnboxingScene {
  resize(width: number, height: number): void;
  draw(time: number): void;
  dispose(): void;
}

function contactTexture() {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 128;
  const ctx = canvas.getContext("2d")!;
  const gradient = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
  gradient.addColorStop(0, "rgba(53,34,15,.45)");
  gradient.addColorStop(.35, "rgba(53,34,15,.22)");
  gradient.addColorStop(1, "rgba(53,34,15,0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(canvas);
}

export function createUnboxingScene(canvas: HTMLCanvasElement, portrait: HTMLCanvasElement, packaging: UnboxingPackage): UnboxingScene {
  const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true, premultipliedAlpha: true });
  renderer.setPixelRatio(Math.max(2, window.devicePixelRatio || 1));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.16;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.localClippingEnabled = true;
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-2.5, 2.5, 1.8, -1.8, .1, 30);
  camera.position.set(.65, 3.15, 11);
  camera.lookAt(0, 1.12, 0);
  const room = new RoomEnvironment();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const environment = pmrem.fromScene(room, .04);
  scene.environment = environment.texture;
  scene.environmentIntensity = .72;
  room.dispose();
  pmrem.dispose();

  scene.add(new THREE.HemisphereLight(0xfff9ed, 0xc8b8a2, 2.0));
  const key = new THREE.DirectionalLight(0xfff5e4, 3.1);
  key.position.set(-3.5, 6, 5);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.camera.left = key.shadow.camera.bottom = -4;
  key.shadow.camera.right = key.shadow.camera.top = 4;
  key.shadow.camera.near = .5;
  key.shadow.camera.far = 18;
  key.shadow.normalBias = .018;
  key.shadow.bias = -.0002;
  key.shadow.radius = 4;
  key.target.position.set(0, .5, 0);
  scene.add(key, key.target);
  const fill = new THREE.DirectionalLight(0xe8efff, .65);
  fill.position.set(4, 3, 1);
  scene.add(fill);

  const weave = weaveTexture();
  const paper = new THREE.MeshPhysicalMaterial({
    color: 0xeaddc8, roughness: .76, metalness: 0, side: THREE.DoubleSide,
    bumpMap: weave, bumpScale: .0035, sheen: .15, sheenRoughness: .85, sheenColor: new THREE.Color(0xf4e7cf),
  });
  const lining = paper.clone();
  lining.color.set(0xcab493);
  lining.roughness = .92;
  const cloth = new THREE.MeshPhysicalMaterial({
    color: 0x8e9d78, roughness: .88, metalness: 0, side: THREE.DoubleSide,
    bumpMap: weave, bumpScale: .012, sheen: 1, sheenColor: new THREE.Color(0xc1c9aa), sheenRoughness: .8,
  });
  const floorMaterial = new THREE.ShadowMaterial({ color: 0x493a2a, opacity: .20 });
  const ground = mesh(new THREE.PlaneGeometry(12, 12), floorMaterial);
  ground.rotation.x = -Math.PI / 2;
  ground.position.y = -.012;
  ground.castShadow = false;
  scene.add(ground);

  const gift = new THREE.Group();
  scene.add(gift);
  let movingLid: THREE.Group | undefined;
  let paperRibbon: THREE.Group | undefined;
  let lidRestHeight = 0;
  const petals: PaperPetal[] = [];
  const floorHeight = packaging === "paper-fold" ? .045 : .19;
  let characterX = 0;
  if (packaging === "soft-tray") {
    gift.add(vessel([
      [1.17, .83, .24, .02], [1.23, .89, .28, .075],
      [1.25, .90, .29, .14], [1.25, .90, .29, .43],
      [1.235, .885, .28, .49], [1.20, .85, .26, .515],
      [1.165, .815, .235, .49], [1.14, .79, .22, .25],
      [1.09, .74, .20, .19],
    ], paper, lining));
    movingLid = new THREE.Group();
    const shell = lid(1.265, .915, .29, paper, lining);
    shell.position.z = .88;
    const ribbon = tiedRibbon(1.26, .91, .15, cloth);
    shell.add(ribbon);
    movingLid.add(shell);
    movingLid.position.set(0, .515, -.88);
    gift.add(movingLid);
  } else if (packaging === "round-box") {
    gift.position.x = -.36;
    characterX = -.36;
    gift.add(vessel([
      [.98, .98, .98, .015], [1.015, 1.015, 1.015, .045],
      [1.025, 1.025, 1.025, .10], [1.025, 1.025, 1.025, .56],
      [1.02, 1.02, 1.02, .615], [.99, .99, .99, .64],
      [.96, .96, .96, .615], [.955, .955, .955, .27],
      [.92, .92, .92, .19],
    ], paper, lining));
    movingLid = lid(1.05, 1.05, 1.05, paper, lining);
    movingLid.add(tiedRibbon(1.045, 1.045, .15, cloth));
    gift.add(movingLid);
    movingLid.rotation.set(1.13, -.10, -.43);
    lidRestHeight = -new THREE.Box3().setFromObject(movingLid).min.y + .012;
    movingLid.rotation.set(0, 0, 0);
  } else {
    const wrapping = paper.clone();
    wrapping.color.set(0xead7b8);
    wrapping.roughness = .87;
    wrapping.bumpScale = .006;
    wrapping.thickness = .004;
    for (let side = 0; side < 4; side++) {
      const petal = paperPetal(side, wrapping);
      petals.push(petal);
      gift.add(petal.object);
    }
    const pad = mesh(new THREE.BoxGeometry(1.87, .032, 1.37, 1, 1, 1), wrapping);
    pad.position.y = .022;
    gift.add(pad);
    paperRibbon = tiedRibbon(.94, .69, 1.26, cloth);
    gift.add(paperRibbon);
  }
  const warmth = new THREE.PointLight(0xffc16d, 0, 3.5, 2);
  warmth.position.set(0, .8, .05);
  gift.add(warmth);

  const portraitTexture = new THREE.CanvasTexture(portrait);
  portraitTexture.colorSpace = THREE.SRGBColorSpace;
  portraitTexture.generateMipmaps = false;
  portraitTexture.minFilter = THREE.LinearFilter;
  portraitTexture.magFilter = THREE.LinearFilter;
  const clip = new THREE.Plane(new THREE.Vector3(0, 1, 0), -floorHeight);
  const portraitMaterial = new THREE.MeshBasicMaterial({
    map: portraitTexture, transparent: true, alphaTest: .02, depthWrite: true,
    toneMapped: false, side: THREE.DoubleSide, clippingPlanes: [clip],
  });
  const character = mesh(new THREE.PlaneGeometry(2.36, 2.36), portraitMaterial);
  character.quaternion.copy(camera.quaternion);
  character.receiveShadow = false;
  character.customDepthMaterial = new THREE.MeshDepthMaterial({
    map: portraitTexture, alphaTest: .08, depthPacking: THREE.RGBADepthPacking, clippingPlanes: [clip],
  });
  scene.add(character);
  const shadowTexture = contactTexture();
  const contact = new THREE.Mesh(new THREE.PlaneGeometry(1.65, .74), new THREE.MeshBasicMaterial({
    map: shadowTexture, transparent: true, depthWrite: false, toneMapped: false,
  }));
  contact.rotation.x = -Math.PI / 2;
  contact.position.set(characterX, floorHeight + .007, 0);
  scene.add(contact);
  const up = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
  let previousOpen = -1;
  const wrappingMaterials = new Set<THREE.Material>();
  gift.traverse(object => {
    if (!(object instanceof THREE.Mesh)) return;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    materials.forEach(material => { material.transparent = true; wrappingMaterials.add(material); });
  });

  return {
    resize(width, height) {
      renderer.setPixelRatio(Math.max(2, window.devicePixelRatio || 1));
      renderer.setSize(width, height, false);
      const aspect = width / Math.max(1, height), halfHeight = 1.76;
      camera.left = -halfHeight * aspect;
      camera.right = halfHeight * aspect;
      camera.top = halfHeight;
      camera.bottom = -halfHeight;
      camera.updateProjectionMatrix();
    },
    draw(time) {
      const state = sampleUnboxing(time);
      gift.visible = state.packaging > 0;
      wrappingMaterials.forEach(material => {
        material.opacity = state.packaging;
        material.depthWrite = state.packaging === 1;
      });
      if (movingLid) {
        if (packaging === "soft-tray") {
          movingLid.rotation.x = -state.open * 1.73;
        } else {
          // Lift vertically first; only then rotate and lower onto the right-hand edge.
          const travel = THREE.MathUtils.smoothstep(state.open, .23, 1);
          movingLid.position.set(1.66 * travel, .64 + .70 * Math.sin(Math.PI * state.open) + (lidRestHeight - .64) * travel, .35 * travel);
          movingLid.rotation.set(1.13 * travel, -.10 * travel, -.43 * travel);
        }
      }
      if (state.open !== previousOpen) {
        petals.forEach(petal => petal.update(state.open));
        previousOpen = state.open;
      }
      if (paperRibbon) {
        paperRibbon.visible = state.untie < 1;
        paperRibbon.position.set(-.5 * state.untie, 1.26 + .18 * Math.sin(state.untie * Math.PI), -3.8 * state.untie);
        paperRibbon.rotation.z = -.25 * state.untie;
      }
      warmth.intensity = packaging === "paper-fold" ? 2.6 * Math.sin(Math.PI * state.open) : 0;
      character.visible = state.reveal > 0;
      contact.visible = state.reveal > .5;
      const scale = 1 + .12 * state.approach;
      const standingHeight = THREE.MathUtils.lerp(floorHeight, .03, state.approach);
      const x = characterX * (1 - state.approach), z = .32 * state.approach;
      character.scale.setScalar(scale);
      character.position.set(x, standingHeight + state.jump - 2.15 * (1 - state.reveal), z).addScaledVector(up, 1.015 * scale);
      clip.constant = -THREE.MathUtils.lerp(floorHeight, -.15, state.approach);
      contact.position.set(x, standingHeight + .007, z);
      contact.scale.setScalar(1 + .12 * state.approach - state.jump);
      contact.material.opacity = 1 - state.jump * 2;
      portraitTexture.needsUpdate = true;
      renderer.render(scene, camera);
    },
    dispose() {
      const geometries = new Set<THREE.BufferGeometry>();
      const materials = new Set<THREE.Material>();
      scene.traverse(object => {
        if (!(object instanceof THREE.Mesh)) return;
        geometries.add(object.geometry);
        if (Array.isArray(object.material)) object.material.forEach(material => materials.add(material));
        else materials.add(object.material);
      });
      geometries.forEach(geometry => geometry.dispose());
      materials.forEach(material => material.dispose());
      character.customDepthMaterial?.dispose();
      weave.dispose(); portraitTexture.dispose(); shadowTexture.dispose(); environment.dispose();
      key.shadow.dispose(); renderer.dispose();
    },
  };
}
