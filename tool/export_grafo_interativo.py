#!/usr/bin/env python3
"""Gera o dashboard sci-fi do grafo Graphify: grafo_interativo.html.

Uso: python3 tool/export_grafo_interativo.py
Entrada: graphify-out/graph.json (AST + nos semanticos)
Saida:   grafo_interativo.html (raiz do repo, dados embutidos — funciona em file://)

Recursos do dashboard:
  - Modo 2D TATICO (vis-network local, offline) com animacao de formacao
    estilo Obsidian (replay + velocidade ajustavel).
  - Modo 3D ORBITAL (3d-force-graph via CDN) com rotacao em varios eixos.
  - Filtros por modulo, grau minimo, busca, destaque de vizinhanca.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import networkx as nx

ROOT = Path(__file__).resolve().parent.parent
GRAPH_JSON = ROOT / "graphify-out" / "graph.json"
OUT_HTML = ROOT / "grafo_interativo.html"

MODULE_COLORS = {
    "lib/core": "#c084fc",
    "lib/ui": "#22d3ee",
    "lib/views": "#34d399",
    "lib/drivers": "#fbbf24",
    "lib/main": "#f472b6",
    "lib/outros": "#818cf8",
    "android": "#4ade80",
    "linux": "#f97316",
    "windows": "#60a5fa",
    "test": "#e879f9",
    "tool": "#94a3b8",
    "docs": "#facc15",
    "outros": "#64748b",
}


def module_of(source_file: str) -> str:
    sf = (source_file or "").replace("\\", "/").lstrip("./")
    if sf.startswith("lib/core"):
        return "lib/core"
    if sf.startswith("lib/ui"):
        return "lib/ui"
    if sf.startswith("lib/views"):
        return "lib/views"
    if sf.startswith("lib/drivers"):
        return "lib/drivers"
    if "main.dart" in sf:
        return "lib/main"
    if sf.startswith("lib/"):
        return "lib/outros"
    for key in ("android", "linux", "windows", "test", "tool"):
        if sf.startswith(key + "/") or sf == key:
            return key
    if sf.endswith((".md", ".yaml", ".yml", ".txt")) or not sf:
        return "docs"
    if sf.startswith((".github/", "docker/")):
        return "docs"
    return "outros"


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CHRONOS // Knowledge Graph</title>
<link rel="stylesheet" href="lib/vis-9.1.2/vis-network.css">
<style>
@font-face { font-family: 'JetBrainsMono'; src: url('assets/fonts/JetBrainsMono-Regular.ttf'); }
:root {
  --bg: #05070f; --panel: rgba(8, 12, 24, 0.92); --line: #1e293b;
  --txt: #dbeafe; --dim: #64748b; --cyan: #22d3ee; --magenta: #f472b6; --amber: #fbbf24;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; background: var(--bg); color: var(--txt);
  font-family: 'JetBrainsMono', monospace; overflow: hidden; }
#bg-grid { position: fixed; inset: 0; z-index: 0; pointer-events: none;
  background-image: radial-gradient(circle at 50% 40%, rgba(34,211,238,0.07), transparent 60%),
    linear-gradient(rgba(34,211,238,0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgba(34,211,238,0.05) 1px, transparent 1px);
  background-size: auto, 44px 44px, 44px 44px; }
#scanlines { position: fixed; inset: 0; z-index: 50; pointer-events: none; opacity: .5;
  background: repeating-linear-gradient(0deg, rgba(255,255,255,0.018) 0 1px, transparent 1px 3px); }
#vignette { position: fixed; inset: 0; z-index: 49; pointer-events: none;
  box-shadow: inset 0 0 180px rgba(0,0,0,0.85); }
#stage { position: fixed; inset: 0; z-index: 1; }
#net2d, #net3d { position: absolute; inset: 0; }
#net3d { display: none; }
/* ---- top bar ---- */
#topbar { position: fixed; top: 0; left: 0; right: 0; z-index: 100; display: flex; align-items: center;
  gap: 14px; padding: 10px 16px; background: linear-gradient(180deg, rgba(5,7,15,0.95), rgba(5,7,15,0.55) 80%, transparent);
  border-bottom: 1px solid rgba(34,211,238,0.25); }
#topbar .logo { color: var(--cyan); font-weight: bold; letter-spacing: 2px; font-size: 15px;
  text-shadow: 0 0 12px rgba(34,211,238,0.8); }
#topbar .sub { color: var(--dim); font-size: 11px; letter-spacing: 1px; }
.tabs { display: flex; gap: 6px; margin-left: 8px; }
.tab { cursor: pointer; border: 1px solid var(--line); background: rgba(15,23,42,0.8); color: var(--txt);
  font-family: inherit; font-size: 12px; letter-spacing: 1px; padding: 7px 14px; border-radius: 4px; }
.tab.active { border-color: var(--cyan); color: #03131a; background: var(--cyan);
  box-shadow: 0 0 16px rgba(34,211,238,0.7); font-weight: bold; }
#stats { margin-left: auto; font-size: 11px; color: var(--dim); text-align: right; line-height: 1.5; }
#stats b { color: var(--cyan); }
/* ---- side panel ---- */
#panel-toggle { position: fixed; top: 64px; right: 12px; z-index: 101; cursor: pointer;
  border: 1px solid var(--cyan); background: var(--panel); color: var(--cyan);
  font-family: inherit; font-size: 12px; padding: 6px 10px; border-radius: 4px; }
#panel { position: fixed; top: 100px; right: 12px; bottom: 12px; width: 300px; z-index: 100;
  background: var(--panel); border: 1px solid rgba(34,211,238,0.35); border-radius: 8px;
  padding: 14px; overflow-y: auto; backdrop-filter: blur(4px);
  box-shadow: 0 0 24px rgba(34,211,238,0.12); }
#panel.hidden { display: none; }
#panel h3 { margin: 14px 0 8px; font-size: 11px; letter-spacing: 2px; color: var(--cyan);
  border-bottom: 1px solid var(--line); padding-bottom: 5px; }
#panel h3:first-child { margin-top: 0; }
#panel label { font-size: 11px; color: var(--dim); display: block; margin: 6px 0 2px; }
#panel input[type="range"] { width: 100%; accent-color: var(--cyan); }
#panel input[type="text"] { width: 100%; background: #0b1120; border: 1px solid var(--line);
  color: var(--txt); font-family: inherit; font-size: 12px; padding: 7px 9px; border-radius: 4px; }
.row { display: flex; gap: 6px; align-items: center; }
.btn { cursor: pointer; flex: 1; border: 1px solid var(--cyan); background: transparent; color: var(--cyan);
  font-family: inherit; font-size: 12px; letter-spacing: 1px; padding: 8px 6px; border-radius: 4px; }
.btn:hover { background: rgba(34,211,238,0.15); }
.btn.warn { border-color: var(--amber); color: var(--amber); }
.btn.warn:hover { background: rgba(251,191,36,0.12); }
.btn.on { background: var(--cyan); color: #03131a; font-weight: bold; }
.mod { display: flex; align-items: center; gap: 8px; font-size: 12px; padding: 3px 0; cursor: pointer; }
.mod .dot { width: 11px; height: 11px; border-radius: 50%; flex-shrink: 0; }
.mod .n { margin-left: auto; color: var(--dim); font-size: 11px; }
.mod.off { opacity: 0.35; }
#progress-wrap { height: 8px; background: #0b1120; border: 1px solid var(--line); border-radius: 4px; overflow: hidden; margin-top: 6px; }
#progress { height: 100%; width: 0%; background: linear-gradient(90deg, var(--cyan), var(--magenta));
  box-shadow: 0 0 10px rgba(34,211,238,0.8); transition: width 0.15s; }
#search-results { max-height: 150px; overflow-y: auto; margin-top: 6px; }
.sr { font-size: 12px; padding: 5px 7px; cursor: pointer; border-radius: 3px; color: var(--txt); }
.sr:hover { background: rgba(34,211,238,0.15); }
.sr small { color: var(--dim); }
/* ---- info card + legend ---- */
#info { position: fixed; left: 12px; bottom: 12px; z-index: 100; max-width: 380px;
  background: var(--panel); border: 1px solid rgba(244,114,182,0.4); border-radius: 8px;
  padding: 12px 14px; font-size: 12px; display: none; }
#info.show { display: block; }
#info .t { color: var(--magenta); font-weight: bold; font-size: 13px; margin-bottom: 4px; }
#info .r { color: var(--dim); line-height: 1.7; word-break: break-word; }
#legend { position: fixed; left: 12px; top: 64px; z-index: 100; background: var(--panel);
  border: 1px solid var(--line); border-radius: 8px; padding: 10px 12px; font-size: 11px; max-width: 230px; }
#legend .mod { cursor: default; }
/* ---- boot splash ---- */
#boot { position: fixed; inset: 0; z-index: 200; background: var(--bg); display: flex;
  align-items: center; justify-content: center; flex-direction: column; gap: 10px;
  transition: opacity 0.5s; }
#boot.gone { opacity: 0; pointer-events: none; }
#boot .big { color: var(--cyan); font-size: 22px; letter-spacing: 4px; text-shadow: 0 0 20px rgba(34,211,238,0.9); }
#boot .small { color: var(--dim); font-size: 12px; letter-spacing: 2px; }
#boot .bar { width: 260px; height: 4px; background: #0b1120; border: 1px solid var(--line); }
#boot .bar i { display: block; height: 100%; width: 40%; background: var(--cyan);
  box-shadow: 0 0 12px var(--cyan); animation: scan 1s linear infinite; }
@keyframes scan { from { margin-left: 0; } to { margin-left: 60%; } }
#err3d { position: absolute; inset: 0; display: none; align-items: center; justify-content: center;
  color: var(--amber); font-size: 13px; text-align: center; padding: 40px; z-index: 5; }
.val { color: var(--cyan); font-size: 11px; }
</style>
</head>
<body>
<div id="bg-grid"></div>
<div id="stage">
  <div id="net2d"></div>
  <div id="net3d"><div id="err3d"></div></div>
</div>
<div id="scanlines"></div>
<div id="vignette"></div>

<div id="topbar">
  <span class="logo">CHRONOS // KNOWLEDGE GRAPH</span>
  <span class="sub">GRAPHIFY · <span id="counts-top">—</span></span>
  <div class="tabs">
    <button class="tab active" id="tab2d">[ 2D TÁTICO ]</button>
    <button class="tab" id="tab3d">[ 3D ORBITAL ]</button>
  </div>
  <div id="stats">nós <b id="st-nodes">—</b> · arestas <b id="st-edges">—</b><br>revelados <b id="st-rev">0</b></div>
</div>

<button id="panel-toggle">[ PAINEL ]</button>
<div id="panel">
  <h3>// FORMAÇÃO (estilo Obsidian)</h3>
  <div class="row">
    <button class="btn" id="btn-play">⏸ PAUSAR</button>
    <button class="btn warn" id="btn-replay">↺ REPLAY</button>
  </div>
  <label>velocidade: <span class="val" id="speed-val">120</span> nós/s</label>
  <input type="range" id="speed" min="10" max="600" value="120">
  <div id="progress-wrap"><div id="progress"></div></div>
  <label style="margin-top:4px;">física 2D: <span class="val" id="phys-val">ON</span></label>
  <div class="row"><button class="btn" id="btn-phys">ALTERNAR FÍSICA</button></div>

  <h3>// FILTROS</h3>
  <label>busca de nó</label>
  <input type="text" id="search" placeholder="ex: scheduler, sync_client..." autocomplete="off">
  <div id="search-results"></div>
  <label>grau mínimo: <span class="val" id="deg-val">1</span></label>
  <input type="range" id="deg" min="1" max="20" value="1">
  <div id="mods"></div>
  <div class="row" style="margin-top:6px">
    <button class="btn" id="btn-all">TODOS</button>
    <button class="btn warn" id="btn-none">NENHUM</button>
  </div>

  <h3>// CONTROLES 3D</h3>
  <div class="row">
    <button class="btn on" id="btn-roty">ÓRBITA Y</button>
    <button class="btn" id="btn-rotx">GIRO X</button>
  </div>
  <label>velocidade orbital: <span class="val" id="orb-val">1.0</span>x</label>
  <input type="range" id="orb" min="0" max="50" value="10">
  <div class="row" style="margin-top:6px"><button class="btn" id="btn-cam">RECENTRAR CÂMERA</button></div>
</div>

<div id="legend"></div>
<div id="info"><div class="t" id="info-t"></div><div class="r" id="info-r"></div></div>

<div id="boot">
  <div class="big">CHRONOS</div>
  <div class="small" id="boot-msg">INICIALIZANDO GRAFO DE CONHECIMENTO...</div>
  <div class="bar"><i></i></div>
</div>

<script src="lib/vis-9.1.2/vis-network.min.js"></script>
<script src="https://unpkg.com/3d-force-graph@1.73.2/dist/3d-force-graph.min.js"></script>
<script>
"use strict";
const NODES = /*__NODES__*/[];
const LINKS = /*__LINKS__*/[];
const MOD_COLORS = /*__MODS__*/{};
const $ = (id) => document.getElementById(id);

/* ---------- estado ---------- */
const state = {
  mode: '2d', playing: true, speed: 120, revealed: 0,
  minDeg: 1, hiddenMods: new Set(), rotY: true, rotX: false, orbSpeed: 1.0,
  net: null, nodes2d: null, edges2d: null, added: new Set(),
  fg3d: null, fgInit: false, selected: null,
};
const order = [...NODES].sort((a, b) => b.deg - a.deg);
const adj = {};
LINKS.forEach(([s, t]) => { (adj[s] = adj[s] || []).push(t); (adj[t] = adj[t] || []).push(s); });
const byId = {}; NODES.forEach(n => byId[n.id] = n);

function visible(n) {
  return !state.hiddenMods.has(n.mod) && n.deg >= state.minDeg;
}
function filteredNodes() { return NODES.filter(visible); }
function filteredLinks(revealedSet) {
  const ok = revealedSet || state.added;
  return LINKS.filter(([s, t]) => ok.has(s) && ok.has(t) && visible(byId[s]) && visible(byId[t]));
}

/* ---------- HUD ---------- */
$('counts-top').textContent = NODES.length + ' NÓS · ' + LINKS.length + ' ARESTAS';
$('legend').innerHTML = '<b style="color:var(--cyan);font-size:10px;letter-spacing:2px;">// MÓDULOS</b>' +
  Object.keys(MOD_COLORS).map(m => {
    const c = NODES.filter(n => n.mod === m).length;
    return c ? `<div class="mod"><span class="dot" style="background:${MOD_COLORS[m]}"></span>${m}<span class="n">${c}</span></div>` : '';
  }).join('');
$('mods').innerHTML = Object.keys(MOD_COLORS).map(m => {
  const c = NODES.filter(n => n.mod === m).length;
  return c ? `<div class="mod" data-mod="${m}"><span class="dot" style="background:${MOD_COLORS[m]}"></span>${m}<span class="n">${c}</span></div>` : '';
}).join('');
document.querySelectorAll('#mods .mod').forEach(el => {
  el.onclick = () => {
    const m = el.dataset.mod;
    if (state.hiddenMods.has(m)) { state.hiddenMods.delete(m); el.classList.remove('off'); }
    else { state.hiddenMods.add(m); el.classList.add('off'); }
    applyFilters();
  };
});

/* ---------- 2D ---------- */
function init2d() {
  state.nodes2d = new vis.DataSet([]);
  state.edges2d = new vis.DataSet([]);
  state.net = new vis.Network($('net2d'), { nodes: state.nodes2d, edges: state.edges2d }, {
    nodes: { shape: 'dot', font: { size: 13, color: '#dbeafe', strokeWidth: 3, strokeColor: '#05070f' },
      borderWidth: 1, borderWidthSelected: 3 },
    edges: { smooth: { type: 'continuous', roundness: 0.4 }, width: 1,
      color: { color: 'rgba(100,116,139,0.4)', highlight: '#22d3ee' } },
    physics: { enabled: true, solver: 'forceAtlas2Based',
      forceAtlas2Based: { gravitationalConstant: -60, centralGravity: 0.25, springLength: 140,
        springConstant: 0.06, damping: 0.85, avoidOverlap: 0.4 },
      stabilization: { enabled: true, iterations: 200, fit: true }, minVelocity: 0.5, maxVelocity: 30 },
    interaction: { hover: true, tooltipDelay: 120, dragNodes: true, dragView: true,
      zoomView: true, navigationButtons: true, multiselect: true },
  });
  state.net.on('click', (p) => {
    if (p.nodes.length) selectNode(p.nodes[0], '2d');
    else clearSelect('2d');
  });
}

function revealBatch() {
  if (!state.playing) return;
  const target = Math.min(order.length, state.revealed + Math.max(1, Math.round(state.speed / 10)));
  const newNodes = [], newEdges = [];
  for (let i = state.revealed; i < target; i++) {
    const n = order[i];
    state.added.add(n.id);
    if (!visible(n)) continue;
    newNodes.push({ id: n.id, label: n.deg >= 4 ? n.label : '', title: tip(n),
      color: n.color, size: n.size, group: n.mod });
  }
  state.revealed = target;
  if (newNodes.length) state.nodes2d.add(newNodes);
  const ids = new Set(newNodes.map(n => n.id));
  LINKS.forEach(([s, t], i) => {
    if ((ids.has(s) && state.added.has(t) && visible(byId[t])) ||
        (ids.has(t) && state.added.has(s) && visible(byId[s]))) {
      try { state.edges2d.add({ id: 'e' + i, from: s, to: t }); } catch (e) { /* duplicada */ }
    }
  });
  const pct = Math.round(100 * state.revealed / order.length);
  $('progress').style.width = pct + '%';
  $('st-rev').textContent = state.revealed + ' (' + pct + '%)';
  if (state.revealed >= order.length) { state.playing = false; $('btn-play').textContent = '▶ INICIAR'; }
  if (state.mode === '3d' && state.fgInit) sync3d();
}

function tip(n) {
  return `<b>${n.label}</b><br>módulo: ${n.mod}<br>arquivo: ${n.file}<br>` +
    `comunidade: ${n.com} · grau: ${n.deg}`;
}

function selectNode(id, from) {
  state.selected = id;
  const n = byId[id];
  $('info-t').textContent = '◈ ' + n.label;
  $('info-r').innerHTML = `módulo: ${n.mod}<br>arquivo: ${n.file}<br>comunidade: ${n.com} · grau: ${n.deg}<br>` +
    `vizinhos: ${(adj[id] || []).length}`;
  $('info').classList.add('show');
  // destaca vizinhança no 2D
  const keep = new Set([id, ...(adj[id] || [])]);
  state.nodes2d.forEach(nd => {
    state.nodes2d.update({ id: nd.id, opacity: keep.has(nd.id) ? 1 : 0.15 });
  });
}
function clearSelect() {
  state.selected = null;
  $('info').classList.remove('show');
  state.nodes2d.forEach(nd => state.nodes2d.update({ id: nd.id, opacity: 1 }));
}

function applyFilters() {
  // reconstrói o 2D respeitando filtros + progresso de revelação
  const revealedIds = new Set(order.slice(0, state.revealed).map(n => n.id));
  const ns = NODES.filter(n => revealedIds.has(n.id) && visible(n)).map(n => ({
    id: n.id, label: n.deg >= 4 ? n.label : '', title: tip(n),
    color: n.color, size: n.size, group: n.mod,
    opacity: state.selected && (n.id !== state.selected && !(adj[state.selected] || []).includes(n.id)) ? 0.15 : 1,
  }));
  const es = LINKS.map(([s, t], i) => ({ id: 'e' + i, from: s, to: t }))
    .filter(e => revealedIds.has(e.from) && revealedIds.has(e.to) && visible(byId[e.from]) && visible(byId[e.to]));
  state.nodes2d.clear(); state.edges2d.clear();
  state.nodes2d.add(ns); state.edges2d.add(es);
  $('st-nodes').textContent = ns.length; $('st-edges').textContent = es.length;
  if (state.mode === '3d' && state.fgInit) sync3d();
}

/* ---------- 3D ---------- */
function init3d() {
  if (typeof ForceGraph3D === 'undefined') {
    $('err3d').style.display = 'flex';
    $('err3d').textContent = '// MODO 3D REQUER INTERNET (CDN unpkg) — o modo 2D funciona offline.';
    return false;
  }
  state.fg3d = ForceGraph3D()($('net3d'))
    .backgroundColor('rgba(0,0,0,0)')
    .nodeColor(n => n.color)
    .nodeRelSize(4)
    .nodeLabel(n => `${n.label} · ${n.mod}`)
    .linkColor(() => 'rgba(100,116,139,0.35)')
    .linkWidth(1)
    .onNodeClick(n => selectNode(n.id, '3d'))
    .onBackgroundClick(() => { $('info').classList.remove('show'); state.selected = null; });
  state.fg3d.controls().enableDamping = true;
  state.fgInit = true;
  sync3d();
  return true;
}
function sync3d() {
  if (!state.fgInit) return;
  const revealedIds = new Set(order.slice(0, state.revealed).map(n => n.id));
  const ns = NODES.filter(n => revealedIds.has(n.id) && visible(n))
    .map(n => ({ id: n.id, label: n.label, color: n.color, val: n.size, mod: n.mod }));
  const inSet = new Set(ns.map(n => n.id));
  const ls = LINKS.filter(([s, t]) => inSet.has(s) && inSet.has(t)).map(([s, t]) => ({ source: s, target: t }));
  state.fg3d.graphData({ nodes: ns, links: ls });
  $('st-nodes').textContent = ns.length; $('st-edges').textContent = ls.length;
}
// rotação multi-eixo
setInterval(() => {
  if (state.mode !== '3d' || !state.fgInit) return;
  if (state.rotY) state.fg3d.autoRotateSpeed = state.orbSpeed;
  else state.fg3d.autoRotateSpeed = 0;
  state.fg3d.autoRotate = state.rotY;
  if (state.rotX) {
    const cam = state.fg3d.camera();
    const angle = 0.003 * state.orbSpeed;
    const y = cam.position.y * Math.cos(angle) - cam.position.z * Math.sin(angle);
    const z = cam.position.y * Math.sin(angle) + cam.position.z * Math.cos(angle);
    cam.position.y = y; cam.position.z = z;
  }
}, 50);

/* ---------- tabs ---------- */
$('tab2d').onclick = () => {
  state.mode = '2d';
  $('tab2d').classList.add('active'); $('tab3d').classList.remove('active');
  $('net2d').style.display = 'block'; $('net3d').style.display = 'none';
};
$('tab3d').onclick = () => {
  state.mode = '3d';
  $('tab3d').classList.add('active'); $('tab2d').classList.remove('active');
  $('net2d').style.display = 'none'; $('net3d').style.display = 'block';
  if (!state.fgInit && !init3d()) return;
  sync3d();
};

/* ---------- controles ---------- */
$('btn-play').onclick = () => {
  if (state.revealed >= order.length) { replay(); return; }
  state.playing = !state.playing;
  $('btn-play').textContent = state.playing ? '⏸ PAUSAR' : '▶ INICIAR';
};
function replay() {
  state.revealed = 0; state.added.clear(); state.playing = true;
  state.nodes2d.clear(); state.edges2d.clear(); clearSelect();
  $('btn-play').textContent = '⏸ PAUSAR';
  if (state.mode === '3d' && state.fgInit) sync3d();
}
$('btn-replay').onclick = replay;
$('speed').oninput = (e) => { state.speed = +e.target.value; $('speed-val').textContent = state.speed; };
$('btn-phys').onclick = () => {
  const on = !state.net.physics.options.enabled;
  state.net.physics.options.enabled = on;
  $('phys-val').textContent = on ? 'ON' : 'OFF';
};
$('deg').oninput = (e) => { state.minDeg = +e.target.value; $('deg-val').textContent = state.minDeg; applyFilters(); };
$('btn-all').onclick = () => { state.hiddenMods.clear();
  document.querySelectorAll('#mods .mod').forEach(el => el.classList.remove('off')); applyFilters(); };
$('btn-none').onclick = () => { state.hiddenMods = new Set(Object.keys(MOD_COLORS));
  document.querySelectorAll('#mods .mod').forEach(el => el.classList.add('off')); applyFilters(); };
$('btn-roty').onclick = (e) => { state.rotY = !state.rotY; e.target.classList.toggle('on', state.rotY); };
$('btn-rotx').onclick = (e) => { state.rotX = !state.rotX; e.target.classList.toggle('on', state.rotX); };
$('orb').oninput = (e) => { state.orbSpeed = +e.target.value / 10; $('orb-val').textContent = state.orbSpeed.toFixed(1); };
$('btn-cam').onclick = () => { if (state.fgInit) state.fg3d.zoomToFit(600); };
$('panel-toggle').onclick = () => $('panel').classList.toggle('hidden');
$('search').oninput = (e) => {
  const q = e.target.value.trim().toLowerCase();
  const box = $('search-results');
  if (q.length < 2) { box.innerHTML = ''; return; }
  const hits = NODES.filter(n => n.label.toLowerCase().includes(q)).slice(0, 12);
  box.innerHTML = hits.map(n => `<div class="sr" data-id="${n.id}">${n.label} <small>${n.mod}</small></div>`).join('') || '<div class="sr">— nada —</div>';
  box.querySelectorAll('.sr[data-id]').forEach(el => {
    el.onclick = () => {
      const id = el.dataset.id;
      if (state.mode === '2d') { state.net.focus(id, { scale: 1.4, animation: true }); selectNode(id, '2d'); }
      else if (state.fgInit) { state.fg3d.centerAt(state.fg3d.graphData().nodes.find(n => n.id === id), 600); selectNode(id, '3d'); }
    };
  });
};
document.addEventListener('keydown', (e) => {
  if (e.key === ' ' && document.activeElement.tagName !== 'INPUT') { e.preventDefault(); $('btn-play').click(); }
  if (e.key === 'r' && document.activeElement.tagName !== 'INPUT') replay();
});

/* ---------- boot ---------- */
init2d();
$('st-nodes').textContent = '0'; $('st-edges').textContent = '0';
setInterval(revealBatch, 100);
setTimeout(() => {
  $('boot').classList.add('gone');
  $('boot-msg').textContent = 'SISTEMA ONLINE';
}, 900);
</script>
</body>
</html>
"""


def main() -> None:
    data = json.loads(GRAPH_JSON.read_text(encoding="utf-8"))
    nodes = data.get("nodes", [])
    links = data.get("links", data.get("edges", []))
    print(f"Graphify: {len(nodes)} nos, {len(links)} arestas")

    G = nx.Graph()
    for n in nodes:
        G.add_node(n["id"])
    for e in links:
        s, t = e.get("source"), e.get("target")
        if isinstance(s, int):
            s = nodes[s]["id"]
        if isinstance(t, int):
            t = nodes[t]["id"]
        if isinstance(s, dict):
            s = s.get("id")
        if isinstance(t, dict):
            t = t.get("id")
        if s in G and t in G and s != t:
            G.add_edge(s, t)
    G.remove_nodes_from(list(nx.isolates(G)))
    degree = dict(G.degree())
    max_deg = max(degree.values()) if degree else 1

    out_nodes = []
    for n in nodes:
        if n["id"] not in G:
            continue
        deg = degree.get(n["id"], 1)
        mod = module_of(str(n.get("source_file", "")))
        out_nodes.append({
            "id": n["id"],
            "label": str(n.get("label", n["id"])),
            "mod": mod,
            "color": MODULE_COLORS.get(mod, MODULE_COLORS["outros"]),
            "size": round(8 + 22 * (deg / max_deg), 1),
            "deg": deg,
            "com": n.get("community", "?"),
            "file": str(n.get("source_file", "?")) + " " + str(n.get("source_location", "")),
        })
    idset = {n["id"] for n in out_nodes}
    out_links = []
    for e in links:
        s, t = e.get("source"), e.get("target")
        if isinstance(s, int):
            s = nodes[s]["id"]
        if isinstance(t, int):
            t = nodes[t]["id"]
        if isinstance(s, dict):
            s = s.get("id")
        if isinstance(t, dict):
            t = t.get("id")
        if s in idset and t in idset and s != t:
            out_links.append([s, t])

    html = HTML_TEMPLATE.replace("/*__NODES__*/[]", json.dumps(out_nodes, ensure_ascii=False))
    html = html.replace("/*__LINKS__*/[]", json.dumps(out_links, ensure_ascii=False))
    html = html.replace("/*__MODS__*/{}", json.dumps(MODULE_COLORS, ensure_ascii=False))
    assert "/*__NODES__*/" not in html, "falha ao injetar nos"
    assert "/*__LINKS__*/" not in html, "falha ao injetar arestas"
    OUT_HTML.write_text(html, encoding="utf-8")
    print(f"OK -> {OUT_HTML} ({OUT_HTML.stat().st_size // 1024} KB, "
          f"{len(out_nodes)} nos, {len(out_links)} arestas)")


if __name__ == "__main__":
    main()
