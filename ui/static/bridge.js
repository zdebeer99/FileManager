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

  for (const name of ['dir-changed', 'settings-changed', 'bookmarks-changed']) {
    listen(name, (event) => send({ id: -1, type: 'event', name, data: event.payload }));
  }

  // Text boxes marked data-select-on-focus select their whole content when focused.
  document.addEventListener('focusin', (event) => {
    if (event.target.dataset && event.target.dataset.selectOnFocus !== undefined) {
      event.target.select();
    }
  });

  // Turn off web-view behaviour that makes no sense in a desktop app
  // (reload, print, find-in-page, the browser context menu).
  const blocked = new Set(['F5', 'F7', 'Ctrl+r', 'Ctrl+p', 'Ctrl+f', 'Ctrl+g', 'Ctrl+u', 'Ctrl+s']);
  window.addEventListener('keydown', (event) => {
    const key = (event.ctrlKey ? 'Ctrl+' : '') + (event.key.length === 1 ? event.key.toLowerCase() : event.key);
    if (blocked.has(key)) event.preventDefault();
  }, true);
  window.addEventListener('contextmenu', (event) => {
    if (!(event.target instanceof HTMLInputElement)) event.preventDefault();
  });
})();
