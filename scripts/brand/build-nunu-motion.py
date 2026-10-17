"""Legacy optical-flow experiment; the client now uses the live layered rig.

Build archived 60 fps transparent clips from the supplied Nunu pose atlas.

Offline only: pip install opencv-python-headless imageio-ffmpeg
Run from the repository root. No model, service, or runtime dependency is used.
"""
from pathlib import Path
import json
import subprocess
import cv2
import imageio_ffmpeg
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'output/brand/nunu/actions-atlas.png'
DEST = ROOT / 'packages/ui/src/assets/nunu'
ARCHIVE = ROOT / 'output/brand/nunu'
FPS, SIZE = 60, 256
# Each entry is an atlas cell followed by its arrival time in seconds.
# Every action starts and ends at the exact same neutral image.
ACTIONS = {
    'wave': [(0, 0), (1, .35), (2, .65), (1, .95), (2, 1.25), (4, 1.6), (0, 2.1)],
    'think': [(0, 0), (7, .4), (8, .85), (9, 1.3), (10, 1.8), (0, 2.4)],
    'cheer': [(0, 0), (13, .35), (14, .75), (15, 1.15), (16, 1.6), (0, 2.1)],
    'sleepy': [(0, 0), (19, .45), (20, 1.0), (21, 1.6), (22, 2.15), (0, 2.7)],
}

atlas = cv2.imread(str(SOURCE), cv2.IMREAD_UNCHANGED)
assert atlas is not None and atlas.shape == (1024, 1536, 4)
raw = [atlas[(i // 6)*SIZE:(i // 6+1)*SIZE, (i % 6)*SIZE:(i % 6+1)*SIZE].copy() for i in range(24)]


def silhouette(image):
    mask = (image[:, :, 3] > 127).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
    largest = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    return (labels == largest).astype(np.uint8)


def core_center(image):
    # Erosion removes fingers and feet, so a raised hand cannot recenter the body.
    core = cv2.erode(silhouette(image), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (35, 35)))
    moments = cv2.moments(core)
    return np.array([moments['m10'], moments['m01']]) / moments['m00']


x, y, w, h = cv2.boundingRect(silhouette(raw[0]))
center = np.array([x + (w-1)/2, y + (h-1)/2])
core = core_center(raw[0])
# Leave enough room for the interpolated silhouette and preserve one stable pivot.
scale = .90
images = []
for original in raw:
    shift = (SIZE-1)/2 - scale * (center + core_center(original) - core)
    transform = np.array([[scale, 0, shift[0]], [0, scale, shift[1]]], dtype=np.float32)
    # Warp premultiplied color to avoid dark or white fringes around translucent fur.
    pixels = original.astype(np.float32) / 255
    # Preserve the fur fringe, but exclude detached atlas specks that optical flow
    # would otherwise drag through the transparent space beside a moving hand.
    support = cv2.dilate(silhouette(original), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    pixels[:, :, 3] *= support
    pixels[:, :, :3] *= pixels[:, :, 3:4]
    images.append(cv2.warpAffine(pixels, transform, (SIZE, SIZE), flags=cv2.INTER_LINEAR))


def rgba_bytes(pixels):
    result = pixels.copy()
    result[:, :, :3] /= np.maximum(result[:, :, 3:4], 1/255)
    return np.round(np.clip(result, 0, 1)*255).astype(np.uint8)


DEST.mkdir(parents=True, exist_ok=True)
poster = rgba_bytes(images[0])
cv2.imwrite(str(DEST / 'portrait-idle.png'), poster)
cv2.imwrite(str(ARCHIVE / 'portrait-idle.png'), poster)

grid = np.stack(np.meshgrid(np.arange(SIZE, dtype=np.float32), np.arange(SIZE, dtype=np.float32)), axis=-1)
flows = {}


def gray(image):
    # Dark neutral background keeps the silhouette visible to optical flow.
    composite = image[:, :, :3] + .18 * (1-image[:, :, 3:4])
    return cv2.cvtColor(np.uint8(np.clip(composite*255, 0, 255)), cv2.COLOR_BGR2GRAY)


def flow(a, b):
    key = (a, b)
    if key not in flows:
        dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        dis.setFinestScale(0)
        dis.setGradientDescentIterations(40)
        dis.setVariationalRefinementIterations(10)
        flows[key] = dis.calc(gray(images[a]), gray(images[b]), None)
    return flows[key]


def remap(image, coordinates):
    return cv2.remap(image, coordinates[:, :, 0], coordinates[:, :, 1], cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)


def intermediate(a, b, progress):
    if progress <= 0:
        return images[a]
    if progress >= 1:
        return images[b]
    # Smooth acceleration at each authored pose, with continuously changing pixels.
    t = progress*progress*(3-2*progress)
    forward, backward = flow(a, b), flow(b, a)
    source_a, source_b = grid.copy(), grid.copy()
    for _ in range(4):
        source_a = grid - t * remap(forward, source_a)
        source_b = grid - (1-t) * remap(backward, source_b)
    return (1-t)*remap(images[a], source_a) + t*remap(images[b], source_b)


manifest = {'fps': FPS, 'size': SIZE, 'source': SOURCE.name, 'neutralBounds': [x, y, w, h], 'actions': {}}
for name, poses in ACTIONS.items():
    target = DEST / f'{name}.webm'
    count = round(poses[-1][1]*FPS)+1
    command = [imageio_ffmpeg.get_ffmpeg_exe(), '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'bgra', '-s', f'{SIZE}x{SIZE}', '-r', str(FPS), '-i', '-', '-an', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-auto-alt-ref', '0', '-crf', '18', '-b:v', '0', '-deadline', 'good', '-cpu-used', '2', str(target)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    for index in range(count):
        time = index/FPS
        segment = next((i for i in range(len(poses)-1) if time <= poses[i+1][1]), len(poses)-2)
        (a, start), (b, end) = poses[segment:segment+2]
        frame = intermediate(a, b, (time-start)/(end-start))
        process.stdin.write(rgba_bytes(frame).tobytes())
    process.stdin.close()
    if process.wait():
        raise RuntimeError(f'Could not encode {name}')
    (ARCHIVE / target.name).write_bytes(target.read_bytes())
    manifest['actions'][name] = {'frames': count, 'duration': count/FPS, 'bytes': target.stat().st_size}
    print(name, manifest['actions'][name], flush=True)
(ARCHIVE / 'motion-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print('Centered neutral bounds:', [x, y, w, h], flush=True)
