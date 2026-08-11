// ── Pure DOM element helpers (no state, no screen logic) ─────────────────────

export function el(tag, className = '') {
  const e = document.createElement(tag);
  if (className) e.className = className;
  return e;
}

export function btn(label, className, onClick) {
  const b = el('button', className);
  b.textContent = label;
  b.onclick = onClick;
  return b;
}

export function chip(label, isWarn) {
  const c = el('div', 'chip' + (isWarn ? ' warn' : ' ok'));
  c.textContent = label;
  return c;
}

export function warningBanner(text) {
  const d = el('div', 'warning-banner');
  d.innerHTML = `<svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor"><path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm.75 10.5h-1.5v-1.5h1.5v1.5zm0-3h-1.5V4.5h1.5V8.5z"/></svg><span>${text}</span>`;
  return d;
}

export function inputField(label, type, value, onChange, placeholder) {
  const f = el('div', 'field');
  const lbl = el('label');
  lbl.textContent = label;
  const inp = document.createElement('input');
  inp.type = type;
  inp.value = value;
  inp.placeholder = placeholder;
  inp.oninput = () => onChange(inp.value);
  f.appendChild(lbl);
  f.appendChild(inp);
  return f;
}
