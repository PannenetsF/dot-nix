'use strict';

const fs = require('node:fs');
const path = require('node:path');

function install(configDir, source = path.join(__dirname, 'sidebar-policy.cjs')) {
  const registry = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins.json'), 'utf8'));
  const radar = registry.find((p) => p.plugin_id === 'hhdebb.herdr-radar' && p.enabled !== false);
  if (!radar?.plugin_root) return 'missing';
  const root = radar.plugin_root;
  const files = ['bin/agent-state.js', 'bin/agent-view.js', 'bin/configure.js', 'bin/settings.js'];
  const marker = "require('../lib/dot-nix-sidebar-policy.cjs');";
  // Fail before any write when a future Radar changes its entrypoint layout.
  const changes = files.map((file) => {
    const dest = path.join(root, file);
    const text = fs.readFileSync(dest, 'utf8');
    if (!text.includes("'use strict';")) throw new Error(`unsupported Radar entrypoint: ${file}`);
    return [dest, text.includes(marker) ? text : text.replace("'use strict';", `'use strict';\n${marker}`)];
  });
  const policyFile = path.join(root, 'lib/dot-nix-sidebar-policy.cjs');
  const policy = fs.readFileSync(source, 'utf8');
  let changed = !fs.existsSync(policyFile) || fs.readFileSync(policyFile, 'utf8') !== policy;
  // Land the module before any entrypoint can start requiring it.
  fs.writeFileSync(policyFile, policy);
  for (const [file, text] of changes) {
    if (fs.readFileSync(file, 'utf8') !== text) { fs.writeFileSync(file, text); changed = true; }
  }
  return changed ? 'changed' : 'unchanged';
}

module.exports = { install };

function installPortal(configDir, source) {
  if (!source || !fs.existsSync(source)) return false;
  const registry = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins.json'), 'utf8'));
  const portal = registry.find((p) => p.plugin_id === 'herdr-portal' && p.enabled !== false);
  if (!portal?.plugin_root) return false;
  const root = portal.plugin_root;
  const dest = path.join(root, 'board/dot_nix_portal_policy.py');
  const policy = fs.readFileSync(source, 'utf8');
  let changed = !fs.existsSync(dest) || fs.readFileSync(dest, 'utf8') !== policy;
  fs.writeFileSync(dest, policy);
  const collector = path.join(root, 'board/collect.py');
  const text = fs.readFileSync(collector, 'utf8');
  const marker = 'import dot_nix_portal_policy as _dn_policy';
  if (!text.includes(marker)) {
    const main = 'if __name__ == "__main__":';
    if (!text.includes(main)) throw new Error('unsupported Portal collector');
    fs.writeFileSync(collector, text.replace(main, `${marker}\n_dn_policy.install(sys.modules[__name__])\n\n${main}`)
      .replace(`${marker}\n`, `import sys\n${marker}\n`));
    changed = true;
  }
  for (const [file, before, after] of [
    ['board/tui.py', 'interval: float = 1.0', 'interval: float = 0.5'],
    ['board/web/app.js', 'setInterval(load, 1500)', 'setInterval(load, 500)'],
  ]) {
    const dest = path.join(root, file);
    const current = fs.readFileSync(dest, 'utf8');
    const next = current.replace(before, after);
    if (next !== current) { fs.writeFileSync(dest, next); changed = true; }
  }
  const unread = registry.find((p) => p.plugin_id === 'to4iki.unread-jump' && p.enabled !== false);
  if (unread?.plugin_root) {
    const file = path.join(unread.plugin_root, 'next.sh');
    const shellQuote = (s) => `'${s.replaceAll("'", "'\\''")}'`;
    const next = `#!/usr/bin/env bash\nset -euo pipefail\nexec python3 ${shellQuote(dest)} --jump ${shellQuote(path.join(root, 'board'))}\n`;
    if (fs.readFileSync(file, 'utf8') !== next) fs.writeFileSync(file, next);
  }
  return changed;
}
module.exports.installPortal = installPortal;
if (require.main === module) {
  (async () => {
    const configDir = process.argv[2];
    const result = install(configDir, process.argv[3]);
    const portalSource = process.env.HERDR_PORTAL_POLICY || path.join(__dirname, 'portal-policy.py');
    const portalChanged = installPortal(configDir, portalSource);
    console.log(result);
    if (result === 'missing') { process.exitCode = 1; return; }
    if (!process.argv.includes('--activate')) return;
    if (portalChanged) {
      const portal = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins.json'), 'utf8'))
        .find((p) => p.plugin_id === 'herdr-portal');
      const daemon = path.join(portal.plugin_root, 'board/daemon.py');
      const python = process.env.HERDR_POLICY_PYTHON || 'python3';
      const spawn = require('node:child_process').spawnSync;
      const status = spawn(python, [daemon, 'status'], {
        env: process.env, encoding: 'utf8', timeout: 20000,
      });
      // Installation must not turn an on-demand dashboard into a service.
      if (status.status === 0) {
        const child = spawn(python, [daemon, 'restart'], {
          env: process.env, encoding: 'utf8', timeout: 20000,
        });
        if (child.status !== 0) throw new Error(child.stderr || child.stdout || 'Portal restart failed');
      }
    }
    const root = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins.json'), 'utf8'))
      .find((p) => p.plugin_id === 'hhdebb.herdr-radar').plugin_root;
    // Plugin action invoke returns before completion. Await stop before start
    // or the new start can find the old daemon healthy, then lose it entirely.
    if (result === 'changed' && !await require(path.join(root, 'lib/stop')).stopAnimator()) {
      throw new Error('Radar did not stop; refusing to start a duplicate');
    }
    const child = require('node:child_process').spawnSync(process.execPath, [path.join(root, 'bin/agent-state.js')], {
      env: process.env, encoding: 'utf8', timeout: 20000,
    });
    if (child.status !== 0) throw new Error(child.stderr || 'Radar start failed');
    let healthy = false;
    for (let attempt = 0; attempt < 30; attempt++) {
      if ((await require(path.join(root, 'lib/state')).daemonStatus()).state === 'healthy') { healthy = true; break; }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    if (!healthy) throw new Error('Radar animator did not become healthy');
    require(path.join(root, 'lib/dot-nix-sidebar-policy.cjs'));
    const reply = await require(path.join(root, 'lib/view')).reassert();
    if (!reply || reply.error) throw new Error('session view was not applied');
  })().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
