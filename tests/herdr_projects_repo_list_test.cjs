'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { install } = require('../config/herdr/install-projects-repo-list.cjs');

test('repo-list installer patches once, rebuilds after failure and skips completed builds', (t) => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'repo-list-install-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const root = path.join(tmp, 'projects');
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(tmp, 'plugins.json'), JSON.stringify([
    { plugin_id: 'herdr-projects', plugin_root: root },
  ]));
  const patch = path.join(__dirname, '../patches/herdr-projects-multiline-repos.patch');
  let applied = false, builds = 0, fail = true;
  const run = (command, args) => {
    if (command === 'git') {
      if (args.includes('--reverse')) return { status: applied ? 0 : 1 };
      if (!args.includes('--check')) applied = true;
      return { status: 0 };
    }
    assert.equal(command, 'cargo');
    builds++;
    if (fail) return { status: 1, stderr: 'build failed' };
    fs.mkdirSync(path.join(root, 'target/release'), { recursive: true });
    fs.writeFileSync(path.join(root, 'target/release/herdr-projects'), 'binary');
    return { status: 0 };
  };
  assert.throws(() => install(tmp, patch, run), /build failed/);
  fail = false;
  assert.equal(install(tmp, patch, run), 'changed');
  assert.equal(install(tmp, patch, run), 'unchanged');
  assert.equal(builds, 2);
});
