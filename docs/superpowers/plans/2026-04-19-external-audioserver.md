# External AudioServer Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When `internal=false` in `plugin.json`, the plugin treats the Lox-Audioserver as external: Start/Stop buttons are disabled, status is checked via HTTP instead of Docker, and the watchdog skips Docker operations.

**Architecture:** Config flag `loxaudioserver.internal` (bool) is the single source of truth. `ajax.cgi` reads it on every `asservicestatus` call to branch between Docker and HTTP. `javascript.js` reads it once at page load via `getconfig` to set button state and poll interval. `as_watchdog.pl` reads it at the top of `start()` and `check()` to bail out early.

**Tech Stack:** Perl (LoxBerry framework), jQuery/jQuery Mobile, LoxBerry::JSON, curl (CLI, used in backticks in ajax.cgi)

---

## File Map

| File | Change |
|------|--------|
| `templates/audioserver.html` | Add `id` to Start/Stop buttons |
| `templates/javascript.js` | Adjust interval (5s→3s/10s), disable buttons when external |
| `webfrontend/html/ajax.cgi` | `asservicestatus`: HTTP check when external; `saveasettings`: call `as_watchdog.pl --action=stop` when saving `internal=false` |
| `bin/as_watchdog.pl` | `start()` and `check()`: read config, return early when `internal=false` |

---

## Task 1: Add IDs to Start/Stop buttons in audioserver.html

**Files:**
- Modify: `templates/audioserver.html:143-144`

- [ ] **Step 1: Add `id` attributes to the two anchor buttons**

  Open `templates/audioserver.html`. Replace lines 143–144:

  ```html
  <a href="#" onclick="asservicerestart(); return false;" class="ui-btn ui-btn-inline ui-mini ui-btn-icon-left ui-icon-check ui-corner-all"><TMPL_VAR "COMMON.BUTTON_RESTART"></a>
  <a href="#" onclick="asservicestop(); return false;" class="ui-btn ui-btn-inline ui-mini ui-btn-icon-left ui-icon-delete ui-corner-all"><TMPL_VAR "COMMON.BUTTON_STOP"></a>
  ```

  with:

  ```html
  <a id="as_btn_restart" href="#" onclick="asservicerestart(); return false;" class="ui-btn ui-btn-inline ui-mini ui-btn-icon-left ui-icon-check ui-corner-all"><TMPL_VAR "COMMON.BUTTON_RESTART"></a>
  <a id="as_btn_stop" href="#" onclick="asservicestop(); return false;" class="ui-btn ui-btn-inline ui-mini ui-btn-icon-left ui-icon-delete ui-corner-all"><TMPL_VAR "COMMON.BUTTON_STOP"></a>
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add templates/audioserver.html
  git commit -m "feat: add IDs to audioserver Start/Stop buttons"
  ```

---

## Task 2: Adjust poll interval and disable buttons in javascript.js

**Files:**
- Modify: `templates/javascript.js`

The current hardcoded interval is 5000 ms. Change it to 3000 ms for internal mode.
In `getconfig()` done-handler, after reading `as.internal`, adjust the interval to 10000 ms
and disable the buttons when `internal=false`.

- [ ] **Step 1: Change the initial interval from 5000 ms to 3000 ms**

  In the `$(function() { ... })` block, find:

  ```javascript
  interval = window.setInterval(function(){ asservicestatus(); }, 5000);
  ```

  Replace with:

  ```javascript
  interval = window.setInterval(function(){ asservicestatus(); }, 3000);
  ```

- [ ] **Step 2: Add interval + button logic to getconfig() done-handler**

  Find this block inside the `getconfig()` done-handler:

  ```javascript
  if (document.getElementById("as_host") && data.loxaudioserver) {
      var as = data.loxaudioserver;
      $("#as_host").val(as.host || "");
      $("#as_port").val(as.port || "");
      var checked = as.internal ? true : false;
      $("#as_internal").prop("checked", checked);
      try { $("#as_internal").flipswitch("refresh"); } catch(e) {}
  }
  ```

  Replace with:

  ```javascript
  if (document.getElementById("as_host") && data.loxaudioserver) {
      var as = data.loxaudioserver;
      $("#as_host").val(as.host || "");
      $("#as_port").val(as.port || "");
      var checked = as.internal ? true : false;
      $("#as_internal").prop("checked", checked);
      try { $("#as_internal").flipswitch("refresh"); } catch(e) {}
      if (!checked) {
          clearInterval(interval);
          interval = window.setInterval(function(){ asservicestatus(); }, 10000);
          $("#as_btn_restart, #as_btn_stop").addClass("ui-disabled").attr("disabled", true);
      }
  }
  ```

- [ ] **Step 3: Verify manually**

  Open the AudioServer page in the browser with `internal=true` in the config.
  Confirm the status badge refreshes approximately every 3 seconds (watch network tab).
  Then set `internal=false` in the config (edit `plugin.json` directly or via the form + save),
  reload the page, confirm both buttons appear greyed out and the poll slows to ~10 seconds.

- [ ] **Step 4: Commit**

  ```bash
  git add templates/javascript.js
  git commit -m "feat: adjust poll interval and disable buttons for external audioserver"
  ```

---

## Task 3: asservicestatus — HTTP check for external mode

**Files:**
- Modify: `webfrontend/html/ajax.cgi`

When `internal=false`, skip Docker and do an HTTP reachability check against `http://host:port`.
Return `{ "pid": "Remote" }` on success (existing JS logic shows this as green), `{}` on failure.

- [ ] **Step 1: Replace the asservicestatus block in ajax.cgi**

  Find the entire block:

  ```perl
  if( $q->{action} eq "asservicestatus" ) {
      my $id;
      my $count = `sudo docker ps | grep -c Up.*lox-audioserver`;
      if ($count >= "1") {
          $id = `sudo docker ps | grep Up.*lox-audioserver | awk '{ print \$1 }'`;
          chomp ($id);
      }
      my %response = ( pid => $id );
      chomp (%response);
      $response = encode_json( \%response );
  }
  ```

  Replace with:

  ```perl
  if( $q->{action} eq "asservicestatus" ) {
      require LoxBerry::JSON;
      my $cfgobj = LoxBerry::JSON->new();
      my $cfg = $cfgobj->open(filename => "$lbpconfigdir/plugin.json", readonly => 1);
      my $internal = ($cfg && $cfg->{loxaudioserver}{internal}) ? 1 : 0;

      if ($internal) {
          my $id;
          my $count = `sudo docker ps | grep -c Up.*lox-audioserver`;
          if ($count >= "1") {
              $id = `sudo docker ps | grep Up.*lox-audioserver | awk '{ print \$1 }'`;
              chomp ($id);
          }
          my %resp = ( pid => $id );
          $response = encode_json( \%resp );
      } else {
          my $host = $cfg->{loxaudioserver}{host} // 'localhost';
          my $port = $cfg->{loxaudioserver}{port} // 7090;
          my $code = `curl -sf --max-time 3 --connect-timeout 3 -o /dev/null -w "%{http_code}" 'http://$host:$port' 2>/dev/null`;
          chomp($code);
          if ($code && $code ne '000') {
              $response = encode_json({ pid => 'Remote' });
          } else {
              $response = encode_json({});
          }
      }
  }
  ```

- [ ] **Step 2: Verify manually**

  With `internal=false` and a reachable external audioserver, open the AudioServer page —
  the status badge should turn green and display "Remote".
  With the external server unreachable, the badge should turn red/"STOPPED".

- [ ] **Step 3: Commit**

  ```bash
  git add webfrontend/html/ajax.cgi
  git commit -m "feat: asservicestatus HTTP check for external audioserver mode"
  ```

---

## Task 4: saveasettings — stop Docker when switching to external

**Files:**
- Modify: `webfrontend/html/ajax.cgi`

When `internal=false` is saved, run `as_watchdog.pl --action=stop` in the background.
The stop sub already writes `as_stopped.cfg`, so nothing else is needed.

- [ ] **Step 1: Add the stop call inside the saveasettings success block**

  Find the `saveasettings` block. Locate the `else` branch after `eval { $jsonobj->write() }`:

  ```perl
          } else {
              # Save version to docker-compose.yml if provided and valid
              if ( defined $q->{version} && $q->{version} =~ /^[\w.\-]+$/ ) {
  ```

  Insert one line immediately after the opening `else {`:

  ```perl
          } else {
              if ( defined $q->{internal} && $q->{internal} == 0 ) {
                  system("$lbpbindir/as_watchdog.pl --action=stop > /dev/null 2>&1 &");
              }
              # Save version to docker-compose.yml if provided and valid
              if ( defined $q->{version} && $q->{version} =~ /^[\w.\-]+$/ ) {
  ```

- [ ] **Step 2: Verify manually**

  With Docker running the local audioserver, switch `internal` to off in the UI and click Save.
  After a few seconds, run `sudo docker ps` — the lox-audioserver container should be gone.
  `$lbpconfigdir/as_stopped.cfg` should exist.

- [ ] **Step 3: Commit**

  ```bash
  git add webfrontend/html/ajax.cgi
  git commit -m "feat: stop local audioserver when switching to external mode"
  ```

---

## Task 5: as_watchdog.pl — skip Docker when internal=false

**Files:**
- Modify: `bin/as_watchdog.pl`

Read `plugin.json` at the start of `start()` and `check()`. If `internal=false`, log and return
immediately without touching Docker or `as_stopped.cfg`.

- [ ] **Step 1: Add early-return to start()**

  Find the `start` sub. Its current opening is:

  ```perl
  sub start
  {

      # Start with:
      if (-e  "$lbpconfigdir/as_stopped.cfg") {
          unlink("$lbpconfigdir/as_stopped.cfg");
      }
  ```

  Insert the external check **before** the `as_stopped.cfg` block:

  ```perl
  sub start
  {

      my $cfgobj2 = LoxBerry::JSON->new();
      my $cfg2 = $cfgobj2->open(filename => "$lbpconfigdir/plugin.json", readonly => 1);
      if ($cfg2 && !$cfg2->{loxaudioserver}{internal}) {
          LOGINF "Lox-Audioserver ist als extern konfiguriert – kein Start erforderlich.";
          return(0);
      }

      # Start with:
      if (-e  "$lbpconfigdir/as_stopped.cfg") {
          unlink("$lbpconfigdir/as_stopped.cfg");
      }
  ```

- [ ] **Step 2: Add early-return to check()**

  Find the `check` sub. Its current opening is:

  ```perl
  sub check
  {

      LOGINF "Checking Status of Lox-Audioserver...";

      if (-e  "$lbpconfigdir/as_stopped.cfg") {
  ```

  Insert the external check **after** the LOGINF line, before the `as_stopped.cfg` check:

  ```perl
  sub check
  {

      LOGINF "Checking Status of Lox-Audioserver...";

      my $cfgobj2 = LoxBerry::JSON->new();
      my $cfg2 = $cfgobj2->open(filename => "$lbpconfigdir/plugin.json", readonly => 1);
      if ($cfg2 && !$cfg2->{loxaudioserver}{internal}) {
          LOGINF "Lox-Audioserver ist als extern konfiguriert – kein Check erforderlich.";
          return(0);
      }

      if (-e  "$lbpconfigdir/as_stopped.cfg") {
  ```

- [ ] **Step 3: Verify manually**

  Set `internal=false` in `plugin.json`. Run:

  ```bash
  perl bin/as_watchdog.pl --action=start --verbose=1
  perl bin/as_watchdog.pl --action=check --verbose=1
  ```

  Both should log the "extern konfiguriert" message and exit without touching Docker.

- [ ] **Step 4: Commit**

  ```bash
  git add bin/as_watchdog.pl
  git commit -m "feat: skip Docker start/check when audioserver is external"
  ```

---

## Task 6: Push all commits to GitHub

- [ ] **Step 1: Push**

  ```bash
  git push origin HEAD:main
  ```

- [ ] **Step 2: Verify**

  Confirm the 5 new commits appear on `https://github.com/mschlenstedt/LoxBerry-Plugin-Audioserver4Home`.
