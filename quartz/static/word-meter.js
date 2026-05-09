void function () {
  var CAPTION_WINDOW_MS = 30000;
  var SHORT_WINDOW_MS = 60000;
  var LONG_WINDOW_MS = 600000;
  var TICK_MS = 200;

  var recognition, listening, startedAt, totalWords, wordEvents, captionEntries, finalIndex, tickHandle, restartTimer, cleanupNav;

  function getRecognitionConstructor() {
    return window.SpeechRecognition || window.webkitSpeechRecognition || null;
  }

  function init() {
    var host = document.getElementById('word-meter');
    if (!host) return null;
    host.innerHTML = '';
    host.appendChild(buildUi());

    var Ctor = getRecognitionConstructor();
    if (!Ctor) {
      showUnsupported();
      return cleanup;
    }

    var btn = document.getElementById('wm-toggle');
    btn.addEventListener('click', toggleListening);

    return cleanup;
  }

  function buildUi() {
    var root = document.createElement('div');
    root.style.cssText = 'font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;color:#e7eef5;background:linear-gradient(180deg,#0b1320,#0a1729);border-radius:14px;padding:24px 20px;box-shadow:0 8px 30px rgba(0,0,0,0.25);max-width:760px;margin:0 auto;';
    root.innerHTML = [
      '<div id="wm-status" style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;text-align:center;margin-bottom:12px;">idle</div>',
      '<div id="wm-count" style="font-size:clamp(72px,18vw,160px);font-weight:700;line-height:1;text-align:center;font-variant-numeric:tabular-nums;letter-spacing:-0.04em;color:#f6fbff;">0</div>',
      '<div id="wm-count-label" style="font-size:14px;text-align:center;color:#7e95b3;margin-top:6px;">words spoken</div>',
      '<div style="display:flex;justify-content:center;margin:22px 0 14px;">',
      '  <button id="wm-toggle" type="button" style="font:600 16px/1 inherit;padding:14px 28px;border-radius:999px;border:0;background:#2aa198;color:#001019;cursor:pointer;min-width:180px;">Start counting</button>',
      '</div>',
      '<div id="wm-meta" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-top:18px;">',
      '  <div style="background:rgba(255,255,255,0.04);border-radius:10px;padding:12px;text-align:center;">',
      '    <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;">Started</div>',
      '    <div id="wm-started" style="font-size:15px;margin-top:4px;color:#cfe0f2;">—</div>',
      '  </div>',
      '  <div style="background:rgba(255,255,255,0.04);border-radius:10px;padding:12px;text-align:center;">',
      '    <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;">Last 1 min</div>',
      '    <div id="wm-rate-short" style="font-size:22px;font-weight:600;margin-top:2px;font-variant-numeric:tabular-nums;color:#f6fbff;">0</div>',
      '    <div style="font-size:11px;color:#7e95b3;">words / minute</div>',
      '  </div>',
      '  <div style="background:rgba(255,255,255,0.04);border-radius:10px;padding:12px;text-align:center;">',
      '    <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;">Last 10 min</div>',
      '    <div id="wm-rate-long" style="font-size:22px;font-weight:600;margin-top:2px;font-variant-numeric:tabular-nums;color:#f6fbff;">0</div>',
      '    <div style="font-size:11px;color:#7e95b3;">words / minute</div>',
      '  </div>',
      '  <div style="background:rgba(255,255,255,0.04);border-radius:10px;padding:12px;text-align:center;">',
      '    <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;">Overall</div>',
      '    <div id="wm-rate-overall" style="font-size:22px;font-weight:600;margin-top:2px;font-variant-numeric:tabular-nums;color:#f6fbff;">0</div>',
      '    <div style="font-size:11px;color:#7e95b3;">words / minute</div>',
      '  </div>',
      '</div>',
      '<div style="margin-top:22px;">',
      '  <div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#7e95b3;margin-bottom:6px;">Recent captions <span style="text-transform:none;letter-spacing:0;color:#54708f;">(last 30 s)</span></div>',
      '  <div id="wm-captions" aria-live="polite" style="background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.05);border-radius:10px;padding:12px;min-height:96px;font-size:15px;line-height:1.5;color:#cfe0f2;overflow:hidden;"></div>',
      '</div>',
      '<div id="wm-error" role="alert" style="margin-top:12px;font-size:13px;color:#ff8b94;text-align:center;min-height:18px;"></div>',
      '<div style="margin-top:14px;font-size:11px;color:#54708f;text-align:center;line-height:1.5;">',
      '  Uses the browser&rsquo;s built-in Web Speech API. Audio handling depends on your browser:',
      '  Safari processes locally on-device; Chrome typically streams audio to Google for recognition.',
      '  Nothing is sent or stored by this page.',
      '</div>'
    ].join('');
    return root;
  }

  function showUnsupported() {
    setError('Your browser does not support the Web Speech API. Try Chrome, Edge, or Safari.');
    var btn = document.getElementById('wm-toggle');
    if (btn) { btn.disabled = true; btn.style.opacity = '0.5'; btn.style.cursor = 'not-allowed'; }
    setStatus('unsupported');
  }

  function toggleListening() {
    if (listening) stopListening('idle');
    else startListening();
  }

  function startListening() {
    var Ctor = getRecognitionConstructor();
    if (!Ctor) { showUnsupported(); return; }

    setError('');
    totalWords = 0;
    wordEvents = [];
    captionEntries = [];
    finalIndex = 0;
    startedAt = Date.now();

    recognition = new Ctor();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = (navigator.language || 'en-US');

    recognition.onresult = onResult;
    recognition.onerror = onError;
    recognition.onend = onEnd;

    listening = true;
    setButton('Stop counting', '#dc322f', '#ffffff');
    setStatus('listening');
    updateStarted();
    renderCount();
    renderRates();
    renderCaptions();
    tickHandle = setInterval(tick, TICK_MS);

    safeStart();
  }

  function safeStart() {
    try { recognition.start(); }
    catch (err) {
      // start() throws if already started; ignore that case.
      if (!/already started/i.test(String(err && err.message || err))) {
        setError('Could not start recognition: ' + (err && err.message || err));
      }
    }
  }

  function stopListening(statusText) {
    listening = false;
    if (recognition) {
      recognition.onresult = null; recognition.onerror = null; recognition.onend = null;
      try { recognition.stop(); } catch (e) { /* noop */ }
      recognition = null;
    }
    if (tickHandle) { clearInterval(tickHandle); tickHandle = null; }
    if (restartTimer) { clearTimeout(restartTimer); restartTimer = null; }
    setButton('Start counting', '#2aa198', '#001019');
    setStatus(statusText || 'idle');
  }

  function onResult(event) {
    var now = Date.now();
    for (var i = event.resultIndex; i < event.results.length; i++) {
      var result = event.results[i];
      if (!result.isFinal) continue;
      // Only count each finalized result once.
      if (i < finalIndex) continue;
      finalIndex = i + 1;
      var transcript = (result[0] && result[0].transcript) || '';
      var words = countWords(transcript);
      if (words > 0) {
        totalWords += words;
        wordEvents.push({ t: now, n: words });
      }
      pushCaption(transcript.trim(), now);
    }
    renderCount();
    renderRates();
    renderCaptions();
  }

  function onError(event) {
    var code = event && event.error;
    if (code === 'no-speech' || code === 'aborted' || code === 'audio-capture') {
      // Transient; recognition will fire `onend` and we will restart.
      return;
    }
    if (code === 'not-allowed' || code === 'service-not-allowed') {
      setError('Microphone permission denied. Allow microphone access and try again.');
      stopListening('permission denied');
      return;
    }
    if (code === 'network') {
      setError('Network error reaching the speech service.');
      return;
    }
    setError('Recognition error: ' + (code || 'unknown'));
  }

  function onEnd() {
    if (!listening) return;
    // Chromium auto-stops after silence; restart promptly to maintain ambient capture.
    restartTimer = setTimeout(function () {
      if (listening && recognition) safeStart();
    }, 250);
  }

  function countWords(text) {
    if (!text) return 0;
    var matches = text.trim().match(/\S+/g);
    return matches ? matches.length : 0;
  }

  function pushCaption(text, now) {
    if (!text) return;
    captionEntries.push({ t: now, text: text });
    pruneCaptions(now);
  }

  function pruneCaptions(now) {
    var cutoff = now - CAPTION_WINDOW_MS;
    while (captionEntries.length && captionEntries[0].t < cutoff) {
      captionEntries.shift();
    }
    var eventCutoff = now - LONG_WINDOW_MS;
    while (wordEvents.length && wordEvents[0].t < eventCutoff) {
      wordEvents.shift();
    }
  }

  function tick() {
    pruneCaptions(Date.now());
    renderRates();
    renderCaptions();
    renderStartedRelative();
  }

  function wordsInWindow(windowMs) {
    var now = Date.now();
    var cutoff = now - windowMs;
    var sum = 0;
    for (var i = wordEvents.length - 1; i >= 0; i--) {
      if (wordEvents[i].t < cutoff) break;
      sum += wordEvents[i].n;
    }
    var elapsed = Math.min(windowMs, now - (startedAt || now));
    if (elapsed <= 0) return 0;
    return sum * 60000 / elapsed;
  }

  function renderCount() {
    setText('wm-count', String(totalWords || 0));
  }

  function renderRates() {
    setText('wm-rate-short', formatRate(wordsInWindow(SHORT_WINDOW_MS)));
    setText('wm-rate-long', formatRate(wordsInWindow(LONG_WINDOW_MS)));
    var elapsed = startedAt ? Math.max(1, Date.now() - startedAt) : 1;
    setText('wm-rate-overall', formatRate((totalWords || 0) * 60000 / elapsed));
  }

  function formatRate(value) {
    if (!isFinite(value) || value <= 0) return '0';
    if (value >= 100) return String(Math.round(value));
    return value.toFixed(1);
  }

  function renderCaptions() {
    var node = document.getElementById('wm-captions');
    if (!node) return;
    if (!captionEntries.length) {
      node.innerHTML = '<span style="color:#54708f;font-style:italic;">Waiting for speech…</span>';
      return;
    }
    var now = Date.now();
    var html = captionEntries.map(function (entry) {
      var age = (now - entry.t) / CAPTION_WINDOW_MS;
      var alpha = Math.max(0.15, 1 - age);
      return '<span style="opacity:' + alpha.toFixed(2) + ';">' + escapeHtml(entry.text) + '</span>';
    }).join(' ');
    node.innerHTML = html;
  }

  function renderStartedRelative() {
    if (!startedAt) return;
    var ageSec = Math.floor((Date.now() - startedAt) / 1000);
    var rel = formatDuration(ageSec);
    var clock = formatClock(new Date(startedAt));
    setText('wm-started', clock + ' · ' + rel + ' ago');
  }

  function updateStarted() {
    if (!startedAt) { setText('wm-started', '—'); return; }
    setText('wm-started', formatClock(new Date(startedAt)) + ' · just now');
  }

  function formatClock(date) {
    try {
      return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
    } catch (e) {
      return date.toISOString().slice(11, 19);
    }
  }

  function formatDuration(totalSeconds) {
    if (totalSeconds < 60) return totalSeconds + 's';
    var minutes = Math.floor(totalSeconds / 60);
    var seconds = totalSeconds % 60;
    if (minutes < 60) return minutes + 'm ' + seconds + 's';
    var hours = Math.floor(minutes / 60);
    var remMinutes = minutes % 60;
    return hours + 'h ' + remMinutes + 'm';
  }

  function escapeHtml(text) {
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function setText(id, value) {
    var node = document.getElementById(id);
    if (node) node.textContent = value;
  }

  function setStatus(text) {
    setText('wm-status', text);
  }

  function setError(text) {
    var node = document.getElementById('wm-error');
    if (node) node.textContent = text || '';
  }

  function setButton(label, bg, fg) {
    var btn = document.getElementById('wm-toggle');
    if (!btn) return;
    btn.textContent = label;
    btn.style.background = bg;
    btn.style.color = fg;
  }

  function cleanup() {
    if (listening) stopListening('idle');
    if (tickHandle) { clearInterval(tickHandle); tickHandle = null; }
    if (restartTimer) { clearTimeout(restartTimer); restartTimer = null; }
  }

  // Expose internals for headless verification only when explicitly enabled.
  if (window.__WM_TEST_HOOK__) {
    window.__wordMeter = {
      getState: function () {
        return {
          listening: !!listening,
          totalWords: totalWords || 0,
          captions: (captionEntries || []).map(function (entry) { return entry.text; }),
          startedAt: startedAt || null
        };
      },
      simulateResult: function (text, isFinal) {
        var result = [{ transcript: text }];
        result.isFinal = !!isFinal;
        var startIndex = finalIndex;
        var pad = [];
        for (var k = 0; k < startIndex; k++) pad.push({ isFinal: true, 0: { transcript: '' } });
        var event = { resultIndex: startIndex, results: pad.concat([result]) };
        onResult(event);
      },
      reset: function () { stopListening('idle'); }
    };
  }

  var stop = init();
  document.addEventListener('nav', function () {
    if (cleanupNav) cleanupNav();
    cleanupNav = init();
  });
  cleanupNav = stop;
}();
