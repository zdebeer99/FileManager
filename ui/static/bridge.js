// Connects the Elm ports to the Tauri backend. Keep this file small:
// application logic belongs in Elm (UI) or Rust (everything else).
//
//   Elm -> Rust:  toBackend   { id, cmd, args, stream }
//   Rust -> Elm:  fromBackend { id, type: 'ok' | 'err' | 'stream' | 'event', data, name? }
(function () {
  'use strict';

  const { invoke, Channel } = window.__TAURI__.core;
  const { listen } = window.__TAURI__.event;

  const app = Elm.Main.init({ node: document.getElementById('app') });
  const send = (message) => app.ports.fromBackend.send(message);

  app.ports.toBackend.subscribe(({ id, cmd, args, stream }) => {
    const callArgs = Object.assign({}, args);
    if (stream) {
      const channel = new Channel();
      channel.onmessage = (data) => send({ id, type: 'stream', data });
      callArgs.onEvent = channel;
    }
    invoke(cmd, callArgs).then(
      (data) => send({ id, type: 'ok', data: data === undefined ? null : data }),
      (error) => send({ id, type: 'err', data: String((error && error.message) || error) })
    );
  });

  // Elm can't select part of a text box; wait for the redraw, then select.
  app.ports.selectText.subscribe(({ id, start, end }) => {
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const box = document.getElementById(id);
      if (box) {
        box.focus();
        box.setSelectionRange(start, end);
      }
    }));
  });

  // Files dropped from other apps: find the folder under the pointer
  // (elements marked data-drop) before passing the drop to Elm.
  listen('file-drop', (event) => {
    const drop = event.payload;
    const under = document.elementFromPoint(drop.x, drop.y);
    const target = under && under.closest('[data-drop]');
    send({ id: -1, type: 'event', name: 'file-drop', data: Object.assign({}, drop, { target: target ? target.dataset.drop : null }) });
  });

  for (const name of ['dir-changed', 'settings-changed', 'bookmarks-changed', 'colours-changed', 'keybindings-changed', 'toolbar-changed', 'job-progress', 'job-conflict']) {
    listen(name, (event) => send({ id: -1, type: 'event', name, data: event.payload }));
  }

  // A clicked button that disappears leaves focus on the page itself, outside
  // the app's key handler: hand such keys to the app.
  document.addEventListener('keydown', (event) => {
    const root = document.querySelector('.app');
    if (root && (event.target === document.body || event.target === document.documentElement)) {
      root.focus();
      if (!root.dispatchEvent(new KeyboardEvent('keydown', event))) event.preventDefault();
    }
  });

  // Text boxes marked data-select-on-focus select their whole content when focused.
  document.addEventListener('focusin', (event) => {
    if (event.target.dataset && event.target.dataset.selectOnFocus !== undefined) {
      event.target.select();
    }
  });

  // Turn off web-view behaviour that makes no sense in a desktop app
  // (reload, print, find-in-page, the browser context menu).
  const blocked = new Set(['F3', 'F5', 'F7', 'Ctrl+r', 'Ctrl+p', 'Ctrl+f', 'Ctrl+g', 'Ctrl+u', 'Ctrl+s']);
  window.addEventListener('keydown', (event) => {
    const key = (event.ctrlKey ? 'Ctrl+' : '') + (event.key.length === 1 ? event.key.toLowerCase() : event.key);
    if (blocked.has(key)) event.preventDefault();
  }, true);
  window.addEventListener('contextmenu', (event) => {
    if (!(event.target instanceof HTMLInputElement)) event.preventDefault();
  });
})();
