// Word Meter — counts ambient spoken words via the Web Speech API.
// The whole app is wrapped in an IIFE so it can re-init on Quartz `nav` events
// without leaking globals.
void function () {
  'use strict';

  // ---------- Configuration ----------

  const HOST_ELEMENT_ID = 'word-meter';

  const CAPTION_WINDOW_MILLISECONDS = 30_000;
  const SHORT_RATE_WINDOW_MILLISECONDS = 60_000;
  const LONG_RATE_WINDOW_MILLISECONDS = 600_000;
  const TICK_INTERVAL_MILLISECONDS = 200;
  const RESTART_DELAY_MILLISECONDS = 250;

  const MILLISECONDS_PER_MINUTE = 60_000;
  const MILLISECONDS_PER_SECOND = 1_000;
  const MINIMUM_CAPTION_OPACITY = 0.15;

  const PERMISSION_DENIED_ERRORS = ['not-allowed', 'service-not-allowed'];
  const TRANSIENT_ERRORS = ['no-speech', 'aborted', 'audio-capture'];

  const RECOGNITION_MODES = Object.freeze({
    onDevice: { id: 'on-device', label: 'On-device', processLocally: true },
    cloud:    { id: 'cloud',     label: 'Cloud',     processLocally: false }
  });
  const DEFAULT_RECOGNITION_MODE = RECOGNITION_MODES.onDevice;

  const PALETTE = Object.freeze({
    panelBackground: 'linear-gradient(180deg,#0b1320,#0a1729)',
    panelShadow: '0 8px 30px rgba(0,0,0,0.25)',
    primaryText: '#f6fbff',
    secondaryText: '#cfe0f2',
    mutedText: '#7e95b3',
    dimText: '#54708f',
    tileBackground: 'rgba(255,255,255,0.04)',
    captionsBackground: 'rgba(255,255,255,0.03)',
    captionsBorder: '1px solid rgba(255,255,255,0.05)',
    startBackground: '#2aa198',
    startForeground: '#001019',
    stopBackground: '#dc322f',
    stopForeground: '#ffffff',
    errorText: '#ff8b94',
    bodyFont: 'system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif'
  });

  const ELEMENT_IDS = Object.freeze({
    status: 'wm-status',
    count: 'wm-count',
    button: 'wm-toggle',
    started: 'wm-started',
    rateShort: 'wm-rate-short',
    rateLong: 'wm-rate-long',
    rateOverall: 'wm-rate-overall',
    captions: 'wm-captions',
    error: 'wm-error',
    modeOnDevice: 'wm-mode-on-device',
    modeCloud: 'wm-mode-cloud'
  });

  // ---------- Pure utilities ----------

  const countWords = (text) => {
    const matches = String(text || '').trim().match(/\S+/g);
    return matches ? matches.length : 0;
  };

  // Normalize a transcript for refinement-vs-duplicate comparisons. Real-world
  // recognizers re-emit the same utterance with different capitalization
  // (e.g. "Twinkle Twinkle" then "twinkle twinkle") and inconsistent spacing,
  // so we compare on a lowercased, whitespace-collapsed form.
  const normalizeTranscript = (transcript) => String(transcript || '').trim().toLowerCase().replace(/\s+/g, ' ');

  // True iff `candidate` is `prefix` extended by at least one additional word.
  // Requires a word boundary (space) at the join so that "twinkle" → "twinkles"
  // is NOT treated as a refinement of the same utterance.
  const isWordBoundaryExtension = (candidate, prefix) => {
    if (!prefix) return false;
    if (candidate === prefix) return false;
    return candidate.startsWith(prefix + ' ');
  };

  const escapeHtml = (text) => String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

  const formatRate = (wordsPerMinute) => {
    if (!isFinite(wordsPerMinute) || wordsPerMinute <= 0) return '0';
    if (wordsPerMinute >= 100) return String(Math.round(wordsPerMinute));
    return wordsPerMinute.toFixed(1);
  };

  const formatClockTime = (date) => {
    try {
      return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' });
    } catch (_unused) {
      return date.toISOString().slice(11, 19);
    }
  };

  const formatDuration = (totalSeconds) => {
    if (totalSeconds < 60) return `${totalSeconds}s`;
    const totalMinutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    if (totalMinutes < 60) return `${totalMinutes}m ${seconds}s`;
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return `${hours}h ${minutes}m`;
  };

  const wordsInTrailingWindow = (wordEvents, windowMilliseconds, now) => {
    const cutoff = now - windowMilliseconds;
    return wordEvents
      .filter((event) => event.timestamp >= cutoff)
      .reduce((sum, event) => sum + event.wordCount, 0);
  };

  const ratePerMinute = (wordCount, elapsedMilliseconds) => {
    if (elapsedMilliseconds <= 0) return 0;
    return wordCount * MILLISECONDS_PER_MINUTE / elapsedMilliseconds;
  };

  const captionOpacity = (ageMilliseconds) => {
    const fraction = ageMilliseconds / CAPTION_WINDOW_MILLISECONDS;
    return Math.max(MINIMUM_CAPTION_OPACITY, 1 - fraction);
  };

  const isTransientErrorCode = (code) => TRANSIENT_ERRORS.includes(code);
  const isPermissionDeniedCode = (code) => PERMISSION_DENIED_ERRORS.includes(code);

  // ---------- DOM helpers ----------

  const element = (tagName, options = {}) => {
    const node = document.createElement(tagName);
    if (options.id) node.id = options.id;
    if (options.text !== undefined) node.textContent = options.text;
    if (options.html !== undefined) node.innerHTML = options.html;
    if (options.attributes) {
      Object.entries(options.attributes).forEach(([name, value]) => node.setAttribute(name, value));
    }
    if (options.styles) Object.assign(node.style, options.styles);
    if (options.children) options.children.forEach((child) => node.appendChild(child));
    return node;
  };

  const byId = (id) => document.getElementById(id);
  const setText = (id, text) => { const node = byId(id); if (node) node.textContent = text; };
  const setHtml = (id, html) => { const node = byId(id); if (node) node.innerHTML = html; };

  // ---------- UI builders ----------

  const buildStatus = () => element('div', {
    id: ELEMENT_IDS.status,
    text: 'idle',
    styles: {
      fontSize: '13px',
      letterSpacing: '0.08em',
      textTransform: 'uppercase',
      color: PALETTE.mutedText,
      textAlign: 'center',
      marginBottom: '12px'
    }
  });

  const buildBigCount = () => element('div', {
    id: ELEMENT_IDS.count,
    text: '0',
    styles: {
      fontSize: 'clamp(72px,18vw,160px)',
      fontWeight: '700',
      lineHeight: '1',
      textAlign: 'center',
      fontVariantNumeric: 'tabular-nums',
      letterSpacing: '-0.04em',
      color: PALETTE.primaryText
    }
  });

  const buildCountLabel = () => element('div', {
    text: 'words spoken',
    styles: {
      fontSize: '14px',
      textAlign: 'center',
      color: PALETTE.mutedText,
      marginTop: '6px'
    }
  });

  const buildButton = () => element('button', {
    id: ELEMENT_IDS.button,
    text: 'Start counting',
    attributes: { type: 'button' },
    styles: {
      font: '600 16px/1 inherit',
      padding: '14px 28px',
      borderRadius: '999px',
      border: '0',
      background: PALETTE.startBackground,
      color: PALETTE.startForeground,
      cursor: 'pointer',
      minWidth: '180px'
    }
  });

  const buildButtonRow = () => element('div', {
    styles: { display: 'flex', justifyContent: 'center', margin: '22px 0 14px' },
    children: [buildButton()]
  });

  const buildModeRadio = (mode, isDefault) => {
    const input = element('input', {
      id: mode.id === RECOGNITION_MODES.onDevice.id ? ELEMENT_IDS.modeOnDevice : ELEMENT_IDS.modeCloud,
      attributes: {
        type: 'radio',
        name: 'wm-mode',
        value: mode.id,
        ...(isDefault ? { checked: 'checked' } : {})
      },
      styles: { marginRight: '6px', accentColor: PALETTE.startBackground }
    });
    const label = element('label', {
      attributes: { for: input.id },
      styles: {
        display: 'inline-flex',
        alignItems: 'center',
        marginRight: '14px',
        fontSize: '13px',
        color: PALETTE.secondaryText,
        cursor: 'pointer'
      },
      children: [input, element('span', { text: mode.label })]
    });
    return label;
  };

  const buildModeChooser = () => element('div', {
    styles: {
      display: 'flex',
      justifyContent: 'center',
      flexWrap: 'wrap',
      marginBottom: '8px',
      fontSize: '13px',
      color: PALETTE.mutedText
    },
    children: [
      element('span', {
        text: 'Recognition: ',
        styles: { marginRight: '10px', alignSelf: 'center' }
      }),
      buildModeRadio(RECOGNITION_MODES.onDevice, true),
      buildModeRadio(RECOGNITION_MODES.cloud, false)
    ]
  });

  const buildMetricTile = (label, valueId, sublabel) => element('div', {
    styles: {
      background: PALETTE.tileBackground,
      borderRadius: '10px',
      padding: '12px',
      textAlign: 'center'
    },
    children: [
      element('div', {
        text: label,
        styles: {
          fontSize: '11px',
          letterSpacing: '0.08em',
          textTransform: 'uppercase',
          color: PALETTE.mutedText
        }
      }),
      element('div', {
        id: valueId,
        text: valueId === ELEMENT_IDS.started ? '—' : '0',
        styles: {
          fontSize: valueId === ELEMENT_IDS.started ? '15px' : '22px',
          fontWeight: valueId === ELEMENT_IDS.started ? 'normal' : '600',
          marginTop: valueId === ELEMENT_IDS.started ? '4px' : '2px',
          fontVariantNumeric: 'tabular-nums',
          color: valueId === ELEMENT_IDS.started ? PALETTE.secondaryText : PALETTE.primaryText
        }
      }),
      ...(sublabel
        ? [element('div', {
            text: sublabel,
            styles: { fontSize: '11px', color: PALETTE.mutedText }
          })]
        : [])
    ]
  });

  const buildMetricsGrid = () => element('div', {
    styles: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fit,minmax(150px,1fr))',
      gap: '10px',
      marginTop: '18px'
    },
    children: [
      buildMetricTile('Started', ELEMENT_IDS.started),
      buildMetricTile('Last 1 min', ELEMENT_IDS.rateShort, 'words / minute'),
      buildMetricTile('Last 10 min', ELEMENT_IDS.rateLong, 'words / minute'),
      buildMetricTile('Overall', ELEMENT_IDS.rateOverall, 'words / minute')
    ]
  });

  const buildCaptionsPanel = () => element('div', {
    styles: { marginTop: '22px' },
    children: [
      element('div', {
        styles: {
          fontSize: '11px',
          letterSpacing: '0.08em',
          textTransform: 'uppercase',
          color: PALETTE.mutedText,
          marginBottom: '6px'
        },
        children: [
          element('span', { text: 'Recent captions ' }),
          element('span', {
            text: '(last 30 s)',
            styles: { textTransform: 'none', letterSpacing: '0', color: PALETTE.dimText }
          })
        ]
      }),
      element('div', {
        id: ELEMENT_IDS.captions,
        attributes: { 'aria-live': 'polite' },
        styles: {
          background: PALETTE.captionsBackground,
          border: PALETTE.captionsBorder,
          borderRadius: '10px',
          padding: '12px',
          minHeight: '96px',
          fontSize: '15px',
          lineHeight: '1.5',
          color: PALETTE.secondaryText,
          overflow: 'hidden'
        }
      })
    ]
  });

  const buildErrorBanner = () => element('div', {
    id: ELEMENT_IDS.error,
    attributes: { role: 'alert' },
    styles: {
      marginTop: '12px',
      fontSize: '13px',
      color: PALETTE.errorText,
      textAlign: 'center',
      minHeight: '18px'
    }
  });

  const buildPrivacyFooter = () => element('div', {
    text: 'On-device mode keeps audio local when your browser supports it (Safari, recent Chromium). Cloud mode streams audio to your browser vendor’s speech service. Nothing is sent or stored by this page.',
    styles: {
      marginTop: '14px',
      fontSize: '11px',
      color: PALETTE.dimText,
      textAlign: 'center',
      lineHeight: '1.5'
    }
  });

  const buildPanel = () => element('div', {
    styles: {
      fontFamily: PALETTE.bodyFont,
      color: PALETTE.primaryText,
      background: PALETTE.panelBackground,
      borderRadius: '14px',
      padding: '24px 20px',
      boxShadow: PALETTE.panelShadow,
      maxWidth: '760px',
      margin: '0 auto'
    },
    children: [
      buildStatus(),
      buildBigCount(),
      buildCountLabel(),
      buildButtonRow(),
      buildModeChooser(),
      buildMetricsGrid(),
      buildCaptionsPanel(),
      buildErrorBanner(),
      buildPrivacyFooter()
    ]
  });

  // ---------- Recognition shim ----------

  const getRecognitionConstructor = () => window.SpeechRecognition || window.webkitSpeechRecognition || null;

  const selectedMode = () => {
    const cloudRadio = byId(ELEMENT_IDS.modeCloud);
    return cloudRadio && cloudRadio.checked ? RECOGNITION_MODES.cloud : RECOGNITION_MODES.onDevice;
  };

  const configureRecognition = (recognition, mode, locale) => {
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = locale;
    // `processLocally` is the standardized hint for on-device recognition.
    // Browsers that don't implement it ignore the assignment.
    try { recognition.processLocally = mode.processLocally; } catch (_unused) { /* read-only on some builds */ }
    return recognition;
  };

  // ---------- Session lifecycle ----------

  const createSession = () => ({
    listening: false,
    startedAt: null,
    totalWords: 0,
    wordEvents: [],
    captionEntries: [],
    finalIndex: 0,
    // Most recent finalized transcript text in the active recognition run.
    // Used to detect when a new finalized result is a *refinement* of the
    // same utterance (Android Chrome with continuous + interimResults emits
    // each refinement of one utterance as a separate finalized result with
    // the cumulative transcript — see issue #6897), versus a brand new
    // utterance segment.
    lastFinalTranscript: '',
    recognition: null,
    mode: DEFAULT_RECOGNITION_MODE,
    tickHandle: null,
    restartTimer: null
  });

  const session = createSession();

  const startSafely = (recognition) => {
    try {
      recognition.start();
    } catch (err) {
      const message = (err && err.message) || String(err);
      if (!/already started/i.test(message)) {
        showError(`Could not start recognition: ${message}`);
      }
    }
  };

  const beginListening = () => {
    const RecognitionConstructor = getRecognitionConstructor();
    if (!RecognitionConstructor) { showUnsupported(); return; }

    Object.assign(session, {
      listening: true,
      startedAt: Date.now(),
      totalWords: 0,
      wordEvents: [],
      captionEntries: [],
      finalIndex: 0,
      lastFinalTranscript: '',
      mode: selectedMode()
    });

    const locale = navigator.language || 'en-US';
    session.recognition = configureRecognition(new RecognitionConstructor(), session.mode, locale);
    session.recognition.onresult = handleResult;
    session.recognition.onerror = handleError;
    session.recognition.onend = handleEnd;

    showError('');
    setModeChooserEnabled(false);
    setButtonStop();
    setStatus(`listening · ${session.mode.label.toLowerCase()}`);
    renderInitialMeta();
    session.tickHandle = setInterval(handleTick, TICK_INTERVAL_MILLISECONDS);

    startSafely(session.recognition);
  };

  const endListening = (statusText = 'idle') => {
    session.listening = false;
    if (session.recognition) {
      session.recognition.onresult = null;
      session.recognition.onerror = null;
      session.recognition.onend = null;
      try { session.recognition.stop(); } catch (_unused) { /* noop */ }
      session.recognition = null;
    }
    if (session.tickHandle) { clearInterval(session.tickHandle); session.tickHandle = null; }
    if (session.restartTimer) { clearTimeout(session.restartTimer); session.restartTimer = null; }
    setButtonStart();
    setStatus(statusText);
    setModeChooserEnabled(true);
  };

  const toggleListening = () => {
    if (session.listening) endListening('idle');
    else beginListening();
  };

  // ---------- Event handlers ----------

  // Integrate one finalized transcript into the running session totals. This
  // routes each new finalized result into one of four cases relative to the
  // most recent finalized transcript:
  //
  //   1. exact duplicate         → ignore (don't double-count)
  //   2. word-boundary extension → refinement; add only the word delta and
  //                                replace the latest caption in place
  //   3. earlier snapshot        → ignore (older guess re-emitted)
  //   4. otherwise               → new utterance; add full word count and
  //                                push a new caption
  //
  // This is the key fix for issue #6897: Android Chrome (continuous mode +
  // interimResults) emits refinements as additional finalized results, each
  // carrying the full cumulative transcript. Pure index-based dedup counts
  // each refinement as a separate utterance and over-counts dramatically.
  const integrateFinalizedTranscript = (transcript, now) => {
    const newNormalized = normalizeTranscript(transcript);
    if (!newNormalized) return;
    const lastNormalized = normalizeTranscript(session.lastFinalTranscript);

    if (lastNormalized && newNormalized === lastNormalized) {
      // Exact duplicate. Refresh the latest caption's timestamp so it doesn't
      // age out prematurely while the recognizer keeps re-emitting it.
      if (session.captionEntries.length) {
        session.captionEntries[session.captionEntries.length - 1].timestamp = now;
      }
      return;
    }
    if (isWordBoundaryExtension(newNormalized, lastNormalized)) {
      const previousWordCount = countWords(session.lastFinalTranscript);
      const newWordCount = countWords(transcript);
      const delta = newWordCount - previousWordCount;
      session.lastFinalTranscript = transcript;
      if (delta > 0) {
        session.totalWords += delta;
        session.wordEvents.push({ timestamp: now, wordCount: delta });
      }
      if (session.captionEntries.length) {
        session.captionEntries[session.captionEntries.length - 1] = { timestamp: now, text: transcript };
      } else {
        session.captionEntries.push({ timestamp: now, text: transcript });
      }
      return;
    }
    if (isWordBoundaryExtension(lastNormalized, newNormalized)) {
      // Earlier snapshot of the same utterance — ignore.
      return;
    }
    // New utterance segment.
    session.lastFinalTranscript = transcript;
    const wordCount = countWords(transcript);
    if (wordCount > 0) {
      session.totalWords += wordCount;
      session.wordEvents.push({ timestamp: now, wordCount });
    }
    session.captionEntries.push({ timestamp: now, text: transcript });
  };

  const handleResult = (event) => {
    const now = Date.now();
    for (let resultIndex = event.resultIndex; resultIndex < event.results.length; resultIndex++) {
      const result = event.results[resultIndex];
      // Strict boolean check: some recognizer implementations have surfaced
      // truthy non-boolean values for `isFinal`, which would silently let
      // interim guesses leak through a `!result.isFinal` test.
      if (result.isFinal !== true) continue;
      if (resultIndex < session.finalIndex) continue;
      session.finalIndex = resultIndex + 1;
      const transcript = ((result[0] && result[0].transcript) || '').trim();
      if (!transcript) continue;
      integrateFinalizedTranscript(transcript, now);
    }
    pruneOldEntries(now);
    renderCount();
    renderRates();
    renderCaptions();
  };

  const handleError = (event) => {
    const code = event && event.error;
    if (isTransientErrorCode(code)) return;
    if (isPermissionDeniedCode(code)) {
      showError('Microphone permission denied. Allow microphone access and try again.');
      endListening('permission denied');
      return;
    }
    if (code === 'network') {
      showError('Network error reaching the speech service. Try on-device mode if your browser supports it.');
      return;
    }
    if (code === 'language-not-supported') {
      showError('On-device recognition is not available for your language. Switch to cloud mode and try again.');
      endListening('language unavailable');
      return;
    }
    showError(`Recognition error: ${code || 'unknown'}`);
  };

  const handleEnd = () => {
    if (!session.listening) return;
    // event.results restarts at index 0 after a recognition restart, and the
    // user's next utterance after silence should be treated as a brand new
    // utterance rather than a refinement of whatever was last said. Reset
    // the per-recognition-run state here so the auto-restart resumes cleanly.
    session.finalIndex = 0;
    session.lastFinalTranscript = '';
    // Chromium auto-stops after silence; restart promptly to maintain ambient capture.
    session.restartTimer = setTimeout(() => {
      if (session.listening && session.recognition) startSafely(session.recognition);
    }, RESTART_DELAY_MILLISECONDS);
  };

  const handleTick = () => {
    pruneOldEntries(Date.now());
    renderRates();
    renderCaptions();
    renderStartedRelative();
  };

  // ---------- State maintenance ----------

  const pruneOldEntries = (now) => {
    const captionCutoff = now - CAPTION_WINDOW_MILLISECONDS;
    while (session.captionEntries.length && session.captionEntries[0].timestamp < captionCutoff) {
      session.captionEntries.shift();
    }
    const eventCutoff = now - LONG_RATE_WINDOW_MILLISECONDS;
    while (session.wordEvents.length && session.wordEvents[0].timestamp < eventCutoff) {
      session.wordEvents.shift();
    }
  };

  // ---------- Renderers ----------

  const renderCount = () => setText(ELEMENT_IDS.count, String(session.totalWords));

  const renderRates = () => {
    const now = Date.now();
    const elapsed = session.startedAt ? Math.max(1, now - session.startedAt) : 1;
    const shortWords = wordsInTrailingWindow(session.wordEvents, SHORT_RATE_WINDOW_MILLISECONDS, now);
    const longWords = wordsInTrailingWindow(session.wordEvents, LONG_RATE_WINDOW_MILLISECONDS, now);
    const shortElapsed = Math.min(SHORT_RATE_WINDOW_MILLISECONDS, elapsed);
    const longElapsed = Math.min(LONG_RATE_WINDOW_MILLISECONDS, elapsed);
    setText(ELEMENT_IDS.rateShort, formatRate(ratePerMinute(shortWords, shortElapsed)));
    setText(ELEMENT_IDS.rateLong, formatRate(ratePerMinute(longWords, longElapsed)));
    setText(ELEMENT_IDS.rateOverall, formatRate(ratePerMinute(session.totalWords, elapsed)));
  };

  const renderCaptions = () => {
    if (!session.captionEntries.length) {
      setHtml(ELEMENT_IDS.captions, `<span style="color:${PALETTE.dimText};font-style:italic;">Waiting for speech…</span>`);
      return;
    }
    const now = Date.now();
    const captionsHtml = session.captionEntries
      .map((entry) => {
        const opacity = captionOpacity(now - entry.timestamp).toFixed(2);
        return `<span style="opacity:${opacity};">${escapeHtml(entry.text)}</span>`;
      })
      .join(' ');
    setHtml(ELEMENT_IDS.captions, captionsHtml);
  };

  const renderStartedRelative = () => {
    if (!session.startedAt) return;
    const ageSeconds = Math.floor((Date.now() - session.startedAt) / MILLISECONDS_PER_SECOND);
    const clockText = formatClockTime(new Date(session.startedAt));
    const relativeText = formatDuration(ageSeconds);
    setText(ELEMENT_IDS.started, `${clockText} · ${relativeText} ago`);
  };

  const renderInitialMeta = () => {
    setText(ELEMENT_IDS.started, `${formatClockTime(new Date(session.startedAt))} · just now`);
    renderCount();
    renderRates();
    renderCaptions();
  };

  // ---------- UI state setters ----------

  const setStatus = (text) => setText(ELEMENT_IDS.status, text);

  const showError = (text) => {
    const node = byId(ELEMENT_IDS.error);
    if (node) node.textContent = text || '';
  };

  const setButtonAppearance = (label, background, foreground) => {
    const button = byId(ELEMENT_IDS.button);
    if (!button) return;
    button.textContent = label;
    button.style.background = background;
    button.style.color = foreground;
  };

  const setButtonStart = () => setButtonAppearance('Start counting', PALETTE.startBackground, PALETTE.startForeground);
  const setButtonStop = () => setButtonAppearance('Stop counting', PALETTE.stopBackground, PALETTE.stopForeground);

  const setModeChooserEnabled = (enabled) => {
    [ELEMENT_IDS.modeOnDevice, ELEMENT_IDS.modeCloud].forEach((id) => {
      const radio = byId(id);
      if (radio) {
        radio.disabled = !enabled;
        const label = radio.parentElement;
        if (label) label.style.opacity = enabled ? '1' : '0.55';
      }
    });
  };

  const showUnsupported = () => {
    showError('Your browser does not support the Web Speech API. Try Chrome, Edge, or Safari.');
    const button = byId(ELEMENT_IDS.button);
    if (button) {
      button.disabled = true;
      button.style.opacity = '0.5';
      button.style.cursor = 'not-allowed';
    }
    setModeChooserEnabled(false);
    setStatus('unsupported');
  };

  // ---------- Bootstrapping ----------

  const init = () => {
    const host = byId(HOST_ELEMENT_ID);
    if (!host) return () => {};
    host.innerHTML = '';
    host.appendChild(buildPanel());

    if (!getRecognitionConstructor()) {
      showUnsupported();
      return cleanup;
    }

    const button = byId(ELEMENT_IDS.button);
    if (button) button.addEventListener('click', toggleListening);
    return cleanup;
  };

  const cleanup = () => {
    if (session.listening) endListening('idle');
    if (session.tickHandle) { clearInterval(session.tickHandle); session.tickHandle = null; }
    if (session.restartTimer) { clearTimeout(session.restartTimer); session.restartTimer = null; }
  };

  // Test hook — only exposed when explicitly enabled before the script runs.
  if (window.__WM_TEST_HOOK__) {
    window.__wordMeter = {
      getState: () => ({
        listening: session.listening,
        totalWords: session.totalWords,
        captions: session.captionEntries.map((entry) => entry.text),
        startedAt: session.startedAt,
        mode: session.mode.id
      }),
      simulateResult: (text, isFinal) => {
        // SpeechRecognitionResult is array-like with numeric indices plus a boolean
        // `isFinal` property. We faithfully mirror that shape so the production
        // onresult handler exercises the same code paths it would in a real browser.
        const result = [{ transcript: text }];
        result.isFinal = !!isFinal;
        const startIndex = session.finalIndex;
        const padding = Array.from({ length: startIndex }, () => {
          const filler = [{ transcript: '' }];
          filler.isFinal = true;
          return filler;
        });
        handleResult({ resultIndex: startIndex, results: padding.concat([result]) });
      },
      selectMode: (modeId) => {
        const radio = byId(modeId === RECOGNITION_MODES.cloud.id ? ELEMENT_IDS.modeCloud : ELEMENT_IDS.modeOnDevice);
        if (radio) radio.checked = true;
      },
      reset: () => endListening('idle')
    };
  }

  let activeCleanup = init();
  document.addEventListener('nav', () => {
    if (activeCleanup) activeCleanup();
    activeCleanup = init();
  });
}();
