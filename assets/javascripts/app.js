// Phase 1 placeholder - replaced by the built Vue app in phase 3.
const root = document.getElementById('app');
const cfg = JSON.parse(root.dataset.config);
fetch(`${cfg.base}/api/me`, { credentials: 'same-origin', headers: { Accept: 'application/json' } })
  .then((r) => r.json())
  .then((me) => {
    const d = document.createElement('div');
    d.className = 'mui-shell';
    const h = document.createElement('h1'); h.textContent = `Hello, ${me.name}`;
    const a = document.createElement('a'); a.href = me.classic_url; a.textContent = 'Classic view';
    d.append(h, a); root.append(d);
  });
