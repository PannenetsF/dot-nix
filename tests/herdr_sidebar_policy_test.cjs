'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { classify, projects, machineNamespace, FILTER, SORT, install } = require('../config/herdr/sidebar-policy.cjs');
const installer = require('../config/herdr/install-sidebar-policy.cjs');

test('only threads and their descendants are hidden, not manual sessions', () => {
  const catalog = [{ slug: 'nix-hm', name: 'Nix Hm', home: '/projects/nix-hm', repos: ['/repo/nix-hm'], threadRoots: ['/projects/nix-hm/threads', '/worktrees/t1'] }];
  const a = (cwd, role, name = '') => ({ cwd, name, pane_id: 'w:p', tokens: { hp_role: role } });
  for (const agent of [a('/repo/nix-hm', 'other'), a('/projects/nix-hm', 'other'), a('/projects/nix-hm/manual-subdir', 'guest'), a('/unrelated', 'other'), a('/repo/nix-hm-extra', ''), a('/projects/nix-hm', 'coordinator', 'hpc-nix-hm')]) {
    assert.equal(classify(agent, catalog).thread, false, agent.cwd);
  }
  for (const agent of [a('/repo/nix-hm', 'thread'), a('/projects/nix-hm/threads/t-1/sub', ''), a('/worktrees/t1/sub', 'other'), a('/x', '', 'hp-nix-hm-t-0001')]) {
    assert.equal(classify(agent, catalog).thread, true, agent.cwd);
  }
  assert.equal(classify(a('/repo/nix-hm', 'other'), catalog).project.name, 'Nix Hm');
  assert.equal(classify(a('/repo/nix-hm-extra', 'other'), catalog).project, undefined);
});

test('catalog reads worktree roots and renderer/view use the same visible projection', async (t) => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sidebar-policy-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const project = path.join(tmp, 'projects/nix-hm');
  fs.mkdirSync(path.join(project, 'threads'), { recursive: true });
  fs.writeFileSync(path.join(project, 'PROJECT.md'), '+++\nname = "Nix Hm"\n[[repos]]\npath = "/repo/nix-hm"\n+++\n');
  fs.writeFileSync(path.join(project, 'threads/t-0001.toml'), 'worktree_path = "/worktree/t1"\nthread_dir = "/worktree/t1/.herdr-project/task"\n');
  assert.ok(projects(path.join(tmp, 'projects'))[0].threadRoots.includes('/worktree/t1'));
  const root = path.join(tmp, 'radar');
  fs.mkdirSync(path.join(root, 'lib'), { recursive: true });
  const agents = [
    { pane_id: 'con', workspace_id: 'project-space', cwd: project, tokens: { hp_role: 'coordinator' } },
    { pane_id: 'manual', cwd: '/repo/nix-hm', tokens: { hp_role: 'other' } },
    { pane_id: 'thread', cwd: '/worktree/t1/sub', tokens: { hp_role: 'other' } },
    { pane_id: 'manual-cd', workspace_id: 'project-space', cwd: '/tmp/unrelated', tokens: { hp_role: 'other' } },
  ];
  fs.writeFileSync(path.join(root, 'lib/herdr.js'), `module.exports = { projectsEnabled:()=>true, projectDisplayName:()=>null, source:()=>'radar', agentsAsync:async()=>${JSON.stringify(agents)}, workspacesAsync:async()=>[], reportMetadataAsync:async(p,s,t)=>{module.exports.writes.push([p,t]);return true}, writes:[] };`);
  fs.writeFileSync(path.join(root, 'lib/state.js'), `module.exports = {snapshot:async()=>${JSON.stringify(agents.map((a) => ({ pane: a.pane_id })))}};`);
  fs.writeFileSync(path.join(root, 'lib/view.js'), "module.exports = {mode:()=>'recent',apply:()=>null,call:async(m,p)=>p};");
  fs.writeFileSync(path.join(root, 'lib/frame.js'), 'module.exports = {Frame:class {displayOrder(entries){return entries}}};');
  install(root, { projectRoot: path.join(tmp, 'projects') });
  const view = require(path.join(root, 'lib/view'));
  const state = require(path.join(root, 'lib/state'));
  const herdr = require(path.join(root, 'lib/herdr'));
  assert.equal(view.mode(), 'grouped');
  assert.equal(view.resolve('grouped', { op: 'flip' }), 'grouped');
  const snapshot = await state.snapshot();
  assert.equal(snapshot.length, 4, 'thread lifecycle data remains available for Spaces and tab-bar');
  const visible = new (require(path.join(root, 'lib/frame')).Frame)().displayOrder(snapshot);
  assert.deepEqual(visible.map((a) => a.pane), ['con', 'manual', 'manual-cd']);
  const namespace = machineNamespace(path.join(tmp, 'projects'));
  assert.equal(herdr.projectDisplayName(`${namespace}-nix-hm`), 'Nix Hm');
  assert.ok(visible.every((a) => a.hpGroup.startsWith(`${namespace}-nix-hm!`)));
  assert.equal(herdr.writes.find(([p]) => p === 'thread')[1].dn_session, 'thread');
  const spec = await view.apply('recent');
  assert.deepEqual(spec.filter, FILTER);
  assert.deepEqual(spec.sort, SORT);
  assert.equal(spec.filter.value, 'manual');
});

test('aggregate sort never interleaves same-slug projects from different machines', () => {
  const local = machineNamespace('/home/user/.herdr-projects', 'mac');
  const remote = machineNamespace('/home/user/.herdr-projects', 'boe');
  assert.notEqual(local, remote, 'even identical home paths need machine qualification');
  assert.notEqual(local, machineNamespace('/other/.herdr-projects', 'mac'));
  const rows = [
    { machine: local, pane: 'w2:p1', rank: 0, title: 'local coordinator' },
    { machine: remote, pane: 'w2:p1', rank: 0, title: 'boe coordinator' },
    { machine: local, pane: 'w2:p4', rank: 1, title: 'local manual' },
    { machine: remote, pane: 'w2:p4', rank: 1, title: 'Orthus' },
  ].map((row) => ({ ...row, group: `${row.machine}-lagrange-system!${row.rank}!${row.pane}` }));
  rows.sort((a, b) => a.group.localeCompare(b.group));
  for (let i = 0; i < rows.length; i += 2) {
    assert.equal(rows[i].machine, rows[i + 1].machine);
    assert.equal(rows[i].rank, 0);
    assert.equal(rows[i + 1].rank, 1);
  }
  const orthus = rows.findIndex((row) => row.title === 'Orthus');
  assert.equal(rows[orthus - 1].title, 'boe coordinator');
});

test('installer is idempotent and survives replacement of a plugin checkout', (t) => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'sidebar-install-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const root = path.join(tmp, 'radar');
  fs.mkdirSync(path.join(root, 'bin'), { recursive: true });
  fs.mkdirSync(path.join(root, 'lib'));
  fs.writeFileSync(path.join(tmp, 'plugins.json'), JSON.stringify([{ plugin_id: 'hhdebb.herdr-radar', plugin_root: root }]));
  for (const file of ['agent-state.js', 'agent-view.js', 'configure.js', 'settings.js']) fs.writeFileSync(path.join(root, 'bin', file), "#!/usr/bin/env node\n'use strict';\n");
  assert.equal(installer.install(tmp), 'changed');
  assert.equal(installer.install(tmp), 'unchanged');
  assert.equal(fs.readFileSync(path.join(root, 'bin/agent-state.js'), 'utf8').match(/require\(/g).length, 1);
  fs.writeFileSync(path.join(root, 'bin/agent-state.js'), "'use strict';\n");
  assert.equal(installer.install(tmp), 'changed');
});

test('Portal policy and unread entrypoint are installed idempotently together', (t) => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'portal-install-'));
  t.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
  const root = path.join(tmp, 'portal');
  const unread = path.join(tmp, 'unread');
  fs.mkdirSync(path.join(root, 'board/web'), { recursive: true });
  fs.mkdirSync(unread);
  fs.writeFileSync(path.join(root, 'board/collect.py'), 'if __name__ == "__main__":\n    pass\n');
  fs.writeFileSync(path.join(root, 'board/tui.py'), 'interval: float = 1.0');
  fs.writeFileSync(path.join(root, 'board/web/app.js'), 'setInterval(load, 1500)');
  fs.writeFileSync(path.join(unread, 'next.sh'), '#!/bin/bash\n');
  fs.writeFileSync(path.join(tmp, 'plugins.json'), JSON.stringify([
    { plugin_id: 'herdr-portal', plugin_root: root },
    { plugin_id: 'to4iki.unread-jump', plugin_root: unread },
  ]));
  const source = path.join(__dirname, '../config/herdr/portal-policy.py');
  assert.equal(installer.installPortal(tmp, source), true);
  assert.equal(installer.installPortal(tmp, source), false);
  assert.equal(fs.readFileSync(path.join(root, 'board/collect.py'), 'utf8').match(/_dn_policy.install/g).length, 1);
  assert.match(fs.readFileSync(path.join(unread, 'next.sh'), 'utf8'), /--jump/);
  assert.match(fs.readFileSync(path.join(root, 'board/tui.py'), 'utf8'), /0\.5/);
  assert.match(fs.readFileSync(path.join(root, 'board/web/app.js'), 'utf8'), /500/);
});
