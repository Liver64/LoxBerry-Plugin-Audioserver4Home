# External AudioServer Support

**Date:** 2026-04-19

## Overview

When `internal=false` in `plugin.json`, the Lox-Audioserver runs on an external host
(`host:port`) instead of locally via Docker. The plugin must reflect this in the UI,
the status check, and the watchdog behaviour.

## Affected Files

| File | Change |
|------|--------|
| `templates/audioserver.html` | Add `id` attributes to Start/Stop buttons |
| `templates/javascript.js` | Disable buttons, adjust poll interval |
| `webfrontend/html/ajax.cgi` | `saveasettings` stops Docker + creates flag; `asservicestatus` does HTTP check |
| `bin/as_watchdog.pl` | `start` and `check` skip Docker when `internal=false` |

---

## Section 1 — `audioserver.html`

Add `id="as_btn_restart"` and `id="as_btn_stop"` to the two anchor buttons so
JavaScript can target them.

---

## Section 2 — `javascript.js`

### Polling interval

Change the hardcoded `5000` ms interval to `3000` ms for `internal=true`.
After `getconfig()` resolves, if `internal=false`, clear the running interval and
restart it at `10000` ms.

### Button state

In the `getconfig()` done-handler, after populating the form:
- If `internal=false`: add `ui-disabled` class and `disabled` attribute to
  `#as_btn_restart` and `#as_btn_stop`.

### Status display

No change to `asservicestatus()` done-handler. `ajax.cgi` returns
`{ pid: "Remote" }` for a reachable external server, which the existing logic
already renders as green with the pid text.

---

## Section 3 — `ajax.cgi`

### `asservicestatus` action

Read `internal` from `plugin.json`.

- `internal=true` (default): existing `docker ps` check, returns `{ pid: "..." }` or `{}`.
- `internal=false`: HTTP GET to `http://<host>:<port>` with a short timeout (3 s).
  - Reachable → `{ pid: "Remote" }`
  - Not reachable → `{}`

### `saveasettings` action

After saving the config:
- If `internal=false` was saved: run `as_watchdog.pl --action=stop` in the background.
  The stop sub already writes `as_stopped.cfg`, so no separate file creation is needed.
- If `internal=true` was saved: no additional action.

---

## Section 4 — `as_watchdog.pl`

### `start()` sub

Read `plugin.json` at the top of the sub. If `internal=false`:
- Log: "Lox-Audioserver ist als extern konfiguriert – kein Start erforderlich."
- Return immediately without deleting `as_stopped.cfg` or touching Docker.

### `check()` sub

Read `plugin.json` at the top of the sub. If `internal=false`:
- Log: "Lox-Audioserver ist als extern konfiguriert – kein Check erforderlich."
- Return immediately without restarting.

### `stop()` and `restart()` subs

No changes. `stop()` is called by `saveasettings` and writes `as_stopped.cfg`
as a side effect.

---

## Error Handling

- If `as_watchdog.pl --action=stop` fails during save, the config is still written.
  The UI will show the save as successful; the user can stop Docker manually.
- If the HTTP check to the external server times out, `{}` is returned and the
  status shows red/"STOPPED".

---

## Out of Scope

- Automatically starting a local Docker container when switching from `internal=false`
  back to `internal=true` — the user clicks Start manually.
- Stopping the external server remotely.
