'use strict';

// Applied inside Radar, so its keeper, renderer and settings share one policy.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { createHash } = require('node:crypto');

const FILTER = { op: 'eq', field: { token: 'dn_session' }, value: 'manual' };
const SORT = [{ field: { token: 'dn_group' }, order: 'asc' }];

function inside(candidate, root) {
  if (!candidate || !root) return false;
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function machineNamespace(projectRoot, hostname = os.hostname()) {
  // The client sorts all endpoints together. Project slugs and pane IDs are
  // only server-local; qualify the entire key BEFORE its coordinator rank.
  return `machine-${createHash('sha256').update(JSON.stringify([hostname, projectRoot])).digest('hex').slice(0, 16)}`;
}

function scalar(text, key) {
  const raw = text.match(new RegExp(`^${key}\\s*=\\s*("(?:[^"\\\\]|\\\\.)*")`, 'm'))?.[1];
  try { return raw ? JSON.parse(raw) : ''; } catch { return ''; }
}

function projects(root) {
  let dirs;
  try { dirs = fs.readdirSync(root, { withFileTypes: true }); } catch { return []; }
  return dirs.filter((d) => d.isDirectory()).flatMap((dir) => {
    const home = path.join(root, dir.name);
    let text;
    try { text = fs.readFileSync(path.join(home, 'PROJECT.md'), 'utf8'); } catch { return []; }
    const repos = [...text.matchAll(/^path\s*=\s*("(?:[^"\\]|\\.)*")/gm)].flatMap((m) => {
      try { return [JSON.parse(m[1])]; } catch { return []; }
    });
    const threadRoots = [path.join(home, 'threads')];
    try {
      for (const file of fs.readdirSync(path.join(home, 'threads'))) {
        if (!file.endsWith('.toml')) continue;
        const thread = fs.readFileSync(path.join(home, 'threads', file), 'utf8');
        for (const key of ['worktree_path', 'thread_dir']) {
          const value = scalar(thread, key);
          if (value) threadRoots.push(value);
        }
      }
    } catch { /* A new project need not have threads yet. */ }
    return [{ slug: dir.name, home, name: scalar(text, 'name') || dir.name, repos, threadRoots }];
  });
}

function classify(agent, catalog) {
  const cwd = agent.foreground_cwd || agent.cwd || '';
  const tokens = agent.tokens || {};
  const project = catalog.find((p) => tokens.hp_project === p.slug)
    || catalog.find((p) => inside(cwd, p.home))
    || catalog.find((p) => p.threadRoots.some((root) => inside(cwd, root)))
    || catalog.find((p) => p.repos.some((root) => inside(cwd, root)));
  const coordinator = tokens.hp_role === 'coordinator' || /^hpc-/.test(agent.name || '');
  const thread = !coordinator && (tokens.hp_role === 'thread'
    || /^hp-.+-t-\d+/.test(agent.name || '')
    || catalog.some((p) => p.threadRoots.some((root) => inside(cwd, root)))
    || /(?:^|\/)\.herdr-project\//.test(cwd));
  const slug = project?.slug || `zz-manual-${agent.workspace_id || agent.pane_id}`;
  return { thread, project, group: `${slug}!${coordinator ? '0' : '1'}!${agent.pane_id}` };
}

function install(root, options = {}) {
  const herdr = require(path.join(root, 'lib/herdr'));
  const state = require(path.join(root, 'lib/state'));
  const view = require(path.join(root, 'lib/view'));
  const { Frame } = require(path.join(root, 'lib/frame'));
  if (view.dotNixPolicy) return;
  view.dotNixPolicy = true;
  const originalSnapshot = state.snapshot;
  const originalApply = view.apply;
  const originalMode = view.mode;
  const originalResolve = view.resolve;
  const originalName = herdr.projectDisplayName;
  const originalOrder = Frame.prototype.displayOrder;
  const labels = new Map();
  let catalog = [], readAt = 0;
  const projectRoot = options.projectRoot || process.env.HERDR_PROJECTS_ROOT || path.join(os.homedir(), '.herdr-projects');
  const namespace = machineNamespace(projectRoot, options.hostname);
  // The project sidebar is deliberately not a flat recency feed.
  view.mode = () => herdr.projectsEnabled() ? 'grouped' : originalMode();
  view.resolve = (current, request) => herdr.projectsEnabled() ? 'grouped' : originalResolve(current, request);
  view.apply = (mode) => herdr.projectsEnabled()
    ? view.call('agent.view.set', { source: herdr.source(), label: 'sessions', filter: FILTER, sort: SORT })
    : originalApply(mode);
  herdr.projectDisplayName = (slug, now) => labels.get(slug) || originalName(slug, now);
  // Filter only the Agents projection, not the source used for Spaces state,
  // tab-bar activity and lifecycle glyphs of running threads.
  Frame.prototype.displayOrder = function (entries, ...args) {
    return originalOrder.call(this, entries.filter((entry) => !entry.dnHidden), ...args);
  };
  state.snapshot = async () => {
    const entries = await originalSnapshot();
    if (entries === null || !herdr.projectsEnabled()) return entries;
    if (Date.now() - readAt > 5000) { catalog = projects(projectRoot); readAt = Date.now(); }
    const agents = await herdr.agentsAsync();
    if (agents === null) return null;
    const workspaces = new Map((await herdr.workspacesAsync()).map((w) => [w.workspace_id, w.label]));
    const raw = new Map(agents.map((a) => [a.pane_id, a]));
    const workspaceProjects = new Map();
    const threadWorkspaces = new Set(agents.filter((a) => a.tokens?.hp_role === 'thread').map((a) => a.workspace_id));
    for (const agent of agents) {
      if (agent.tokens?.hp_role !== 'coordinator') continue;
      const project = classify(agent, catalog).project;
      if (project) workspaceProjects.set(agent.workspace_id, project);
    }
    // A coordinator can exit or lose its registration while its project
    // workspace stays open. Infer only an unambiguous live project anchor;
    // never let worker workspaces or a shared multi-project workspace claim it.
    const workspaceCandidates = new Map();
    for (const agent of agents) {
      if (!agent.workspace_id) continue;
      const result = classify(agent, catalog);
      if (result.thread || !result.project) continue;
      if (!workspaceCandidates.has(agent.workspace_id)) workspaceCandidates.set(agent.workspace_id, new Map());
      workspaceCandidates.get(agent.workspace_id).set(result.project.slug, result.project);
    }
    for (const [workspace, candidates] of workspaceCandidates) {
      if (!workspaceProjects.has(workspace) && candidates.size === 1) {
        workspaceProjects.set(workspace, candidates.values().next().value);
      }
    }
    const visible = await Promise.all(entries.map(async (entry) => {
      const agent = raw.get(entry.pane);
      if (!agent) return null;
      const result = classify(agent, catalog);
      if (agent.tokens?.hp_role === 'guest' && threadWorkspaces.has(agent.workspace_id)
          && !workspaceProjects.has(agent.workspace_id)) result.thread = true;
      // A manually opened tab belongs to its project workspace even after cd.
      if (!result.project && !result.thread && workspaceProjects.has(agent.workspace_id)) {
        result.project = workspaceProjects.get(agent.workspace_id);
        result.group = `${result.project.slug}!1!${agent.pane_id}`;
      }
      result.group = `${namespace}-${result.group}`;
      const slug = result.group.split('!')[0];
      labels.set(slug, result.project?.name || workspaces.get(agent.workspace_id) || 'Sessions');
      const tokens = { dn_session: result.thread ? 'thread' : 'manual', dn_group: result.group };
      const changed = Object.entries(tokens).some(([key, value]) => agent.tokens?.[key] !== value);
      const ok = !changed || await herdr.reportMetadataAsync(entry.pane, herdr.source(), tokens);
      if (!ok) return null;
      return { ...entry, hpGroup: result.group, hpRole: result.thread ? 'thread' : 'coordinator', dnHidden: result.thread };
    }));
    return visible.filter(Boolean);
  };
}

module.exports = { install, projects, classify, inside, machineNamespace, FILTER, SORT };
if (require.main !== module && path.basename(__filename) === 'dot-nix-sidebar-policy.cjs') install(path.dirname(__dirname));
