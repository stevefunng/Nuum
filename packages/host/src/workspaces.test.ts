import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { test } from 'node:test';
import { WorkspaceStore } from './workspaces.js';

test('personal and room workspaces have stable, distinct ownership and preserve existing files', async () => {
  const root = await realpath(await mkdtemp(path.join(os.tmpdir(), 'nuum-workspaces-')));
  try {
    const store = new WorkspaceStore(path.join(root, 'private'), path.join(root, 'Documents'));
    const personal = await store.ensure('agent:a', '小白', 'personal');
    assert.equal(personal.root, path.join(root, 'Documents/Nuum/小白'));
    await writeFile(path.join(personal.root, 'keep.txt'), 'keep');
    const duplicate = await store.ensure('agent:b', '小白', 'personal');
    assert.notEqual(duplicate.root, personal.root);
    const reopened = new WorkspaceStore(path.join(root, 'private'), path.join(root, 'Documents'));
    assert.deepEqual(await reopened.ensure('agent:a', '改名', 'personal'), personal);
    const room = await store.ensure('room:r', '../小白', 'room');
    assert.equal(path.dirname(room.root), path.join(root, 'Documents/Nuum/Rooms'));
    assert.equal(await readFile(path.join(personal.root, 'keep.txt'), 'utf8'), 'keep');
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('workspace allocation rejects a symlink replacing the managed root', async () => {
  const root = await realpath(await mkdtemp(path.join(os.tmpdir(), 'nuum-workspaces-')));
  try {
    await mkdir(path.join(root, 'Documents'));
    await mkdir(path.join(root, 'outside'));
    await symlink(path.join(root, 'outside'), path.join(root, 'Documents/Nuum'));
    const store = new WorkspaceStore(path.join(root, 'private'), path.join(root, 'Documents'));
    await assert.rejects(store.ensure('agent:a', 'test', 'personal'), /symbolic|symlink/i);
  } finally { await rm(root, { recursive: true, force: true }); }
});
