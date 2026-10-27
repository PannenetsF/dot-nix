'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

function install(configDir, patchFile, run = spawnSync) {
  const registry = JSON.parse(fs.readFileSync(path.join(configDir, 'plugins.json'), 'utf8'));
  const plugin = registry.find((p) => p.plugin_id === 'herdr-projects' && p.enabled !== false);
  if (!plugin?.plugin_root) return 'missing';
  const root = plugin.plugin_root;
  const patch = fs.readFileSync(patchFile, 'utf8');
  const hash = crypto.createHash('sha256').update(patch).digest('hex');
  const stamp = path.join(root, 'target/dot-nix-multiline-repos.sha256');
  const call = (cmd, args, timeout = 10000) => run(cmd, args, {
    cwd: root, encoding: 'utf8', timeout, input: patch,
  });
  const applied = call('git', ['apply', '--reverse', '--check', '-']).status === 0;
  if (!applied) {
    const check = call('git', ['apply', '--check', '-']);
    if (check.status !== 0) throw new Error(`unsupported Projects repo-list source: ${check.stderr}`);
    const result = call('git', ['apply', '-']);
    if (result.status !== 0) throw new Error(result.stderr || 'Projects patch failed');
  }
  if (applied && fs.existsSync(stamp) && fs.readFileSync(stamp, 'utf8') === hash
      && fs.existsSync(path.join(root, 'target/release/herdr-projects'))) return 'unchanged';
  const build = call('cargo', ['build', '--release', '--locked'], 600000);
  if (build.status !== 0) throw new Error(build.stderr || 'Projects build failed');
  fs.mkdirSync(path.dirname(stamp), { recursive: true });
  fs.writeFileSync(stamp, hash);
  return 'changed';
}

module.exports = { install };
if (require.main === module) {
  try { console.log(install(process.argv[2], process.argv[3])); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
