// Word Meter — counts ambient spoken words via the Web Speech API.
// The whole app is wrapped in an IIFE so it can re-init on Quartz `nav` events
// without leaking globals.
void function () {
  'use strict';

  // ---------- Configuration ----------

  // Hard-coded version string. Bump this whenever the served behavior changes
  // in a way users should be able to tell apart. Rendered into the privacy
  // footer and the diagnostics panel.
  const WORD_METER_VERSION = '0.1.0';
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

  // Bumping the version invalidates older persisted shapes so we never feed
  // stale fields into the new code path.
  const STORAGE_KEY = 'word-meter:state:v1';
  const TIMELINE_MAX_RENDERED_ENTRIES = 200;
  const RESET_CONFIRMATION_PROMPT = 'Reset all word meter stats? This cannot be undone.';

  // Recognition strategy.
  //
  // The meter has one user-visible mode. Internally there are two implementations
  // that produce the same outcome: an on-device path (recent Chromium with the
  // `processLocally` extension) and a cloud path (every other configuration of
  // SpeechRecognition that the browser exposes). At runtime the meter always
  // tries the on-device path first and silently falls back to the cloud path if
  // anything goes wrong. The user is not asked to choose, and the page does not
  // expose a chooser. This keeps the UI free of a control that, in practice
  // today, almost no Android browser can actually honor — see specs/word-meter.md
  // for the field telemetry that justifies this choice.
  //
  // ╔═══════════════════════════════════════════════════════════════════════╗
  // ║                                                                       ║
  // ║  If we ever decide to drop the on-device path entirely, the change    ║
  // ║  is purely subtractive:                                               ║
  // ║                                                                       ║
  // ║    1. Delete the section marked `BEGIN on-device path` .. `END        ║
  // ║       on-device path` further down in this file.                      ║
  // ║    2. Delete `ON_DEVICE_PREFLIGHT_ENABLED` below.                     ║
  // ║    3. In `beginListening`, replace the call to                        ║
  // ║       `attemptStart(recognition, locale)` with `startSafely(          ║
  // ║       recognition)`.                                                  ║
  // ║    4. Drop the `language-not-supported` branch in `handleError`.      ║
  // ║                                                                       ║
  // ║  No other call sites or state mutate based on the recognition path,   ║
  // ║  so nothing else needs to change.                                     ║
  // ║                                                                       ║
  // ╚═══════════════════════════════════════════════════════════════════════╝

  const ON_DEVICE_PREFLIGHT_ENABLED = true;

  // The two possible recognition paths. These are internal book-keeping
  // values only — they are never shown to the user.
  const RECOGNITION_PATHS = Object.freeze({
    onDevice: 'on-device',
    cloud: 'cloud'
  });

  // All visual styling lives in `word-meter.css` (alongside this script in
  // `/static/`). The application only applies and removes class names. The
  // stylesheet is loaded relative to this script so the same code works
  // both in production (where the file is served from `/static/`) and in
  // the e2e fixture (where it is served from `/quartz/static/`).
  const STYLESHEET_FILENAME = 'word-meter.css';
  const STYLESHEET_MARKER_ATTRIBUTE = 'data-word-meter-stylesheet';
  const wordMeterScriptElement = typeof document !== 'undefined' ? document.currentScript : null;
  const stylesheetHref = () => {
    if (wordMeterScriptElement && wordMeterScriptElement.src) {
      return wordMeterScriptElement.src.replace(/[^/]+$/, STYLESHEET_FILENAME);
    }
    return '/static/' + STYLESHEET_FILENAME;
  };

  const ELEMENT_IDS = Object.freeze({
    status: 'wm-status',
    count: 'wm-count',
    button: 'wm-toggle',
    resetButton: 'wm-reset',
    started: 'wm-started',
    rateShort: 'wm-rate-short',
    rateLong: 'wm-rate-long',
    rateOverall: 'wm-rate-overall',
    captions: 'wm-captions',
    error: 'wm-error',
    keepAwake: 'wm-keep-awake',
    keepAwakeStatus: 'wm-keep-awake-status',
    timeline: 'wm-timeline',
    timelineEmpty: 'wm-timeline-empty',
    diagnosticsToggle: 'wm-diagnostics-toggle',
    diagnosticsPanel: 'wm-diagnostics',
    diagnosticsContent: 'wm-diagnostics-content',
    diagnosticsCopy: 'wm-diagnostics-copy',
    diagnosticsCopyStatus: 'wm-diagnostics-copy-status',
    version: 'wm-version'
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
    if (options.className) node.className = options.className;
    if (options.text !== undefined) node.textContent = options.text;
    if (options.html !== undefined) node.innerHTML = options.html;
    if (options.attributes) {
      Object.entries(options.attributes).forEach(([name, value]) => node.setAttribute(name, value));
    }
    if (options.children) options.children.forEach((child) => node.appendChild(child));
    return node;
  };

  const ensureStylesheetLinked = () => {
    if (typeof document === 'undefined' || !document.createElement) return;
    const href = stylesheetHref();
    if (document.querySelector && document.querySelector(`link[${STYLESHEET_MARKER_ATTRIBUTE}="${href}"]`)) return;
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = href;
    link.setAttribute(STYLESHEET_MARKER_ATTRIBUTE, href);
    const parent = document.head || document.body;
    if (parent && parent.appendChild) parent.appendChild(link);
  };

  const byId = (id) => document.getElementById(id);
  const setText = (id, text) => { const node = byId(id); if (node) node.textContent = text; };
  const setHtml = (id, html) => { const node = byId(id); if (node) node.innerHTML = html; };

  // ---------- UI builders ----------

  const buildStatus = () => element('div', {
    id: ELEMENT_IDS.status,
    className: 'wm-status',
    text: 'idle'
  });

  const buildBigCount = () => element('div', {
    id: ELEMENT_IDS.count,
    className: 'wm-count',
    text: '0'
  });

  const buildCountLabel = () => element('div', {
    className: 'wm-count-label',
    text: 'words spoken'
  });

  const buildButton = () => element('button', {
    id: ELEMENT_IDS.button,
    className: 'wm-button-pill wm-button-pill-start',
    text: 'Start counting',
    attributes: { type: 'button' }
  });

  const buildResetButton = () => element('button', {
    id: ELEMENT_IDS.resetButton,
    className: 'wm-button-pill-secondary',
    text: 'Reset',
    attributes: { type: 'button', title: 'Clear all stats' }
  });

  const buildButtonRow = () => element('div', {
    className: 'wm-button-row',
    children: [buildButton(), buildResetButton()]
  });

  const buildKeepAwakeToggle = () => {
    const checkbox = element('input', {
      id: ELEMENT_IDS.keepAwake,
      className: 'wm-keep-awake-checkbox',
      attributes: { type: 'checkbox', checked: 'checked' }
    });
    const label = element('label', {
      className: 'wm-keep-awake-label',
      attributes: { for: ELEMENT_IDS.keepAwake },
      children: [
        checkbox,
        element('span', {
          className: 'wm-keep-awake-caption',
          text: '🔋 Keep counting with screen on (recommended)'
        })
      ]
    });
    const status = element('span', {
      id: ELEMENT_IDS.keepAwakeStatus,
      className: 'wm-keep-awake-status',
      text: ''
    });
    return element('div', {
      className: 'wm-keep-awake-row',
      children: [label, status]
    });
  };

  const buildMetricTile = (label, valueId, sublabel) => {
    const isStarted = valueId === ELEMENT_IDS.started;
    return element('div', {
      className: 'wm-metric-tile',
      children: [
        element('div', {
          className: 'wm-metric-tile-label',
          text: label
        }),
        element('div', {
          id: valueId,
          className: isStarted
            ? 'wm-metric-tile-value wm-metric-tile-value-started'
            : 'wm-metric-tile-value',
          text: isStarted ? '—' : '0'
        }),
        ...(sublabel
          ? [element('div', {
              className: 'wm-metric-tile-sublabel',
              text: sublabel
            })]
          : [])
      ]
    });
  };

  const buildMetricsGrid = () => element('div', {
    className: 'wm-metrics-grid',
    children: [
      buildMetricTile('Started', ELEMENT_IDS.started),
      buildMetricTile('Last 1 min', ELEMENT_IDS.rateShort, 'words / minute'),
      buildMetricTile('Last 10 min', ELEMENT_IDS.rateLong, 'words / minute'),
      buildMetricTile('Overall', ELEMENT_IDS.rateOverall, 'words / minute')
    ]
  });

  const buildCaptionsPanel = () => element('div', {
    className: 'wm-section',
    children: [
      element('div', {
        className: 'wm-section-heading',
        children: [
          element('span', { text: 'Recent captions ' }),
          element('span', {
            className: 'wm-section-heading-suffix',
            text: '(last 30 s)'
          })
        ]
      }),
      element('div', {
        id: ELEMENT_IDS.captions,
        className: 'wm-captions-panel',
        attributes: { 'aria-live': 'polite' }
      })
    ]
  });

  const buildErrorBanner = () => element('div', {
    id: ELEMENT_IDS.error,
    className: 'wm-error',
    attributes: { role: 'alert' }
  });

  const buildTimelinePanel = () => element('div', {
    className: 'wm-section',
    children: [
      element('div', {
        className: 'wm-section-heading',
        children: [
          element('span', { text: 'Timeline ' }),
          element('span', {
            className: 'wm-section-heading-suffix',
            text: '(intervals · words · words/min)'
          })
        ]
      }),
      element('div', {
        id: ELEMENT_IDS.timeline,
        className: 'wm-timeline',
        children: [
          element('div', {
            id: ELEMENT_IDS.timelineEmpty,
            className: 'wm-timeline-empty',
            text: 'No intervals yet — press Start counting to begin.'
          })
        ]
      })
    ]
  });

  const buildPrivacyFooter = () => element('div', {
    className: 'wm-privacy-footer',
    children: [
      element('div', {
        text: 'Speech recognition runs in your browser. Nothing is sent or stored by this page.'
      }),
      element('div', {
        id: ELEMENT_IDS.version,
        className: 'wm-privacy-footer-version',
        text: `Word Meter v${WORD_METER_VERSION}`,
        attributes: { 'data-word-meter-version': WORD_METER_VERSION }
      })
    ]
  });

  // The diagnostics panel surfaces every piece of info that helps diagnose why
  // on-device recognition might be failing on one browser but working on
  // another. It is collapsed by default so it doesn't clutter the UI, but a
  // single tap reveals the user agent, Web Speech API support, on-device
  // language-pack API support, the locale being requested, the most recent
  // `available()` and `install()` results, and the most recent recognition
  // error (with full code and message). Each call also logs to the console
  // with a `[word-meter]` prefix so curious users can grep the devtools log.
  const buildDiagnosticsPanel = () => element('details', {
    id: ELEMENT_IDS.diagnosticsPanel,
    className: 'wm-diagnostics-drawer',
    children: [
      element('summary', {
        id: ELEMENT_IDS.diagnosticsToggle,
        className: 'wm-diagnostics-summary',
        text: '🔧 Diagnostics'
      }),
      element('div', {
        className: 'wm-diagnostics-actions',
        children: [
          element('button', {
            id: ELEMENT_IDS.diagnosticsCopy,
            className: 'wm-diagnostics-copy-button',
            text: '📋 Copy diagnostics',
            attributes: { type: 'button', title: 'Copy the snapshot and event log to the clipboard' }
          }),
          element('span', {
            id: ELEMENT_IDS.diagnosticsCopyStatus,
            className: 'wm-diagnostics-copy-status',
            text: ''
          })
        ]
      }),
      element('pre', {
        id: ELEMENT_IDS.diagnosticsContent,
        className: 'wm-diagnostics-content',
        text: 'collecting…'
      })
    ]
  });

  const buildPanel = () => element('div', {
    className: 'wm-panel',
    children: [
      buildStatus(),
      buildBigCount(),
      buildCountLabel(),
      buildButtonRow(),
      buildKeepAwakeToggle(),
      buildMetricsGrid(),
      buildCaptionsPanel(),
      buildErrorBanner(),
      buildTimelinePanel(),
      buildPrivacyFooter(),
      buildDiagnosticsPanel()
    ]
  });

  // ---------- Diagnostics ----------
  //
  // The diagnostics module records every interesting decision the meter makes
  // during a session so that "it didn't work on my browser" reports become
  // diagnosable. Every entry is timestamped, appended to an in-memory log
  // (capped to avoid unbounded growth), echoed to the console with a
  // `[word-meter]` prefix, and rendered into the on-page diagnostics panel.

  const DIAGNOSTICS_MAX_ENTRIES = 60;

  const diagnostics = {
    entries: [],
    snapshot: null
  };

  const recordDiagnostic = (label, detail) => {
    const timestamp = formatClockTime(new Date());
    const renderedDetail = detail === undefined ? '' : (
      typeof detail === 'string' ? detail : safeStringify(detail)
    );
    diagnostics.entries.push({ timestamp, label, detail: renderedDetail });
    if (diagnostics.entries.length > DIAGNOSTICS_MAX_ENTRIES) {
      diagnostics.entries.splice(0, diagnostics.entries.length - DIAGNOSTICS_MAX_ENTRIES);
    }
    try {
      if (typeof console !== 'undefined' && console.log) {
        console.log(`[word-meter ${WORD_METER_VERSION}] ${label}${renderedDetail ? ' — ' + renderedDetail : ''}`);
      }
    } catch (_unused) { /* console unavailable in some embedded contexts */ }
    renderDiagnosticsPanel();
  };

  const safeStringify = (value) => {
    try {
      return JSON.stringify(value, (_key, candidate) => {
        if (candidate instanceof Error) {
          return { name: candidate.name, message: candidate.message };
        }
        return candidate;
      });
    } catch (_unused) {
      return String(value);
    }
  };

  const captureEnvironmentSnapshot = () => {
    const RecognitionConstructor = getRecognitionConstructor();
    const navigatorLanguage = (typeof navigator !== 'undefined' && navigator.language) || '(unknown)';
    const userAgent = (typeof navigator !== 'undefined' && navigator.userAgent) || '(unknown)';
    const wakeLockAvailable = typeof navigator !== 'undefined'
      && !!navigator.wakeLock
      && typeof navigator.wakeLock.request === 'function';
    diagnostics.snapshot = {
      version: WORD_METER_VERSION,
      userAgent,
      navigatorLanguage,
      hasSpeechRecognition: typeof window !== 'undefined' && 'SpeechRecognition' in window,
      hasWebkitSpeechRecognition: typeof window !== 'undefined' && 'webkitSpeechRecognition' in window,
      hasOnDeviceAvailable: !!RecognitionConstructor && typeof RecognitionConstructor.available === 'function',
      hasOnDeviceInstall: !!RecognitionConstructor && typeof RecognitionConstructor.install === 'function',
      wakeLockAvailable
    };
    renderDiagnosticsPanel();
  };

  const formatSnapshot = (snapshot) => {
    if (!snapshot) return '';
    const yes = '✓';
    const no = '✗';
    const flag = (value) => (value ? yes : no);
    return [
      `version           : ${snapshot.version}`,
      `userAgent         : ${snapshot.userAgent}`,
      `navigator.language: ${snapshot.navigatorLanguage}`,
      `SpeechRecognition : ${flag(snapshot.hasSpeechRecognition)}`,
      `webkit prefix     : ${flag(snapshot.hasWebkitSpeechRecognition)}`,
      `on-device API     : available=${flag(snapshot.hasOnDeviceAvailable)} install=${flag(snapshot.hasOnDeviceInstall)}`,
      `Screen Wake Lock  : ${flag(snapshot.wakeLockAvailable)}`
    ].join('\n');
  };

  const formatDiagnostics = () => {
    const header = diagnostics.snapshot ? formatSnapshot(diagnostics.snapshot) + '\n\n' : '';
    const log = diagnostics.entries.length === 0
      ? '(no events yet — press Start counting to populate the log)'
      : diagnostics.entries.map((entry) => {
        const detail = entry.detail ? ' — ' + entry.detail : '';
        return `${entry.timestamp}  ${entry.label}${detail}`;
      }).join('\n');
    return header + log;
  };

  const renderDiagnosticsPanel = () => {
    const target = byId(ELEMENT_IDS.diagnosticsContent);
    if (!target) return;
    target.textContent = formatDiagnostics();
  };

  // Copy the snapshot + event log to the clipboard so a user filing an issue
  // can paste the full diagnostics without having to manually select the
  // <pre> contents on mobile (which is fiddly inside <details>). Falls back
  // to a hidden <textarea> + execCommand('copy') on browsers that don't
  // expose the async Clipboard API or that refuse it in non-secure contexts.
  const copyDiagnostics = async () => {
    const text = formatDiagnostics();
    const showCopyStatus = (message) => setText(ELEMENT_IDS.diagnosticsCopyStatus, message);
    const succeed = () => {
      recordDiagnostic('diagnostics copied to clipboard');
      showCopyStatus('copied!');
      setTimeout(() => showCopyStatus(''), 2000);
    };
    const fail = (reason) => {
      recordDiagnostic('diagnostics copy failed', { reason: String(reason) });
      showCopyStatus('copy failed — long-press the log to select');
      setTimeout(() => showCopyStatus(''), 4000);
    };
    try {
      if (typeof navigator !== 'undefined'
        && navigator.clipboard
        && typeof navigator.clipboard.writeText === 'function') {
        await navigator.clipboard.writeText(text);
        succeed();
        return;
      }
    } catch (error) {
      // fall through to the execCommand fallback below
      recordDiagnostic('clipboard.writeText rejected, falling back', { reason: String(error && error.message || error) });
    }
    try {
      if (typeof document === 'undefined' || !document.createElement) {
        fail('no document');
        return;
      }
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.top = '-1000px';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      const ok = typeof document.execCommand === 'function' && document.execCommand('copy');
      document.body.removeChild(textarea);
      if (ok) succeed(); else fail('execCommand returned false');
    } catch (error) {
      fail(error);
    }
  };

  // ---------- Recognition shim ----------

  const getRecognitionConstructor = () => window.SpeechRecognition || window.webkitSpeechRecognition || null;

  // ╔══════════════════════════════════════════════════════════════════════╗
  // ║ BEGIN on-device path                                                 ║
  // ║                                                                      ║
  // ║ Everything between this banner and `END on-device path` exists to    ║
  // ║ make Chromium's `processLocally` extension work. The standardized    ║
  // ║ on-device API requires the page to call `available()` and, if the    ║
  // ║ pack is `downloadable`, `install()` BEFORE `start()` will accept     ║
  // ║ `processLocally = true`. See:                                        ║
  // ║   https://developer.mozilla.org/docs/Web/API/SpeechRecognition/install_static
  // ║                                                                      ║
  // ║ If on-device support is ever dropped, delete this whole block and    ║
  // ║ follow the migration notes near the top of this file.                ║
  // ╚══════════════════════════════════════════════════════════════════════╝

  const supportsOnDeviceLanguagePackApi = (RecognitionConstructor) =>
    !!RecognitionConstructor
    && typeof RecognitionConstructor.available === 'function'
    && typeof RecognitionConstructor.install === 'function';

  // Returns a promise resolving to one of:
  //   'available'      — language pack present, safe to start on-device
  //   'unavailable'    — browser cannot provide on-device recognition for this language
  //   'install-failed' — download was attempted but did not complete successfully
  //   'unknown'        — browser does not expose the availability/install API
  // The caller is expected to treat anything other than 'available' as a
  // signal to fall back to the cloud path.
  const ensureOnDeviceLanguagePack = (RecognitionConstructor, locale, onDownloadStart) => {
    if (!supportsOnDeviceLanguagePackApi(RecognitionConstructor)) {
      recordDiagnostic('on-device API absent — falling back to cloud', { locale });
      return Promise.resolve('unknown');
    }
    const options = { langs: [locale], processLocally: true };
    recordDiagnostic('SpeechRecognition.available() called', options);
    return Promise.resolve()
      .then(() => RecognitionConstructor.available(options))
      .then((availability) => {
        recordDiagnostic('SpeechRecognition.available() resolved', { availability });
        if (availability === 'available') return 'available';
        if (availability === 'unavailable') return 'unavailable';
        // 'downloadable' or 'downloading' — kick off install and await it.
        if (onDownloadStart) onDownloadStart();
        recordDiagnostic('SpeechRecognition.install() called', options);
        return Promise.resolve()
          .then(() => RecognitionConstructor.install(options))
          .then(
            (installed) => {
              recordDiagnostic('SpeechRecognition.install() resolved', { installed });
              return installed ? 'available' : 'install-failed';
            },
            (installError) => {
              recordDiagnostic('SpeechRecognition.install() rejected', installError);
              return 'install-failed';
            }
          );
      }, (availableError) => {
        recordDiagnostic('SpeechRecognition.available() rejected', availableError);
        return 'unknown';
      });
  };

  // ╔══════════════════════════════════════════════════════════════════════╗
  // ║ END on-device path                                                   ║
  // ╚══════════════════════════════════════════════════════════════════════╝

  const keepAwakeRequested = () => {
    const checkbox = byId(ELEMENT_IDS.keepAwake);
    return !checkbox || checkbox.checked !== false;
  };

  // ---------- Screen Wake Lock ----------
  // The Screen Wake Lock API is the only standardized way for a web page to
  // keep the device's display from sleeping. Without it, the screen locks,
  // the page is suspended, and SpeechRecognition stops — which is why the
  // word meter would otherwise stop counting when the user puts their phone
  // in their pocket. The lock is automatically released by the browser when
  // the page becomes hidden (e.g. user switches tabs), so we re-acquire on
  // `visibilitychange`.

  const wakeLockSupported = () =>
    typeof navigator !== 'undefined'
    && navigator.wakeLock
    && typeof navigator.wakeLock.request === 'function';

  const setKeepAwakeStatus = (text) => setText(ELEMENT_IDS.keepAwakeStatus, text || '');

  const requestWakeLock = async () => {
    if (!wakeLockSupported()) {
      setKeepAwakeStatus('(wake lock not supported on this browser)');
      return;
    }
    try {
      const lock = await navigator.wakeLock.request('screen');
      session.wakeLock = lock;
      setKeepAwakeStatus('screen will stay on');
      lock.addEventListener && lock.addEventListener('release', () => {
        if (session.wakeLock === lock) session.wakeLock = null;
      });
    } catch (err) {
      setKeepAwakeStatus(`(wake lock unavailable: ${(err && err.name) || 'error'})`);
    }
  };

  const releaseWakeLock = async () => {
    setKeepAwakeStatus('');
    const lock = session.wakeLock;
    session.wakeLock = null;
    if (!lock) return;
    try { await lock.release(); } catch (_unused) { /* noop */ }
  };

  const handleVisibilityChange = () => {
    if (typeof document === 'undefined') return;
    // Wake locks auto-release when the page is hidden. Re-acquire on return
    // so brief tab switches don't break a long listening session.
    if (document.visibilityState === 'visible' && session.listening && session.keepAwake && !session.wakeLock) {
      requestWakeLock();
    }
  };

  const configureRecognition = (recognition, processLocally, locale) => {
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = locale;
    // `processLocally` is the standardized hint for on-device recognition.
    // Browsers that don't implement it ignore the assignment. When the meter
    // has decided to fall back to cloud, we explicitly set this to `false`
    // so that any earlier opt-in is unwound.
    try { recognition.processLocally = processLocally; } catch (_unused) { /* read-only on some builds */ }
    return recognition;
  };

  // ---------- Session lifecycle ----------

  const createSession = () => ({
    listening: false,
    // startedAt is the wall-clock start of the *current* listening interval.
    // It is null when idle. The very first start across all intervals is
    // tracked separately as firstStartedAt so totals span every session
    // restored from storage.
    startedAt: null,
    firstStartedAt: null,
    // Completed intervals: [{ startedAt, endedAt, words }]. The interval the
    // user is currently in (if any) lives in currentInterval and is folded
    // into intervals when listening stops.
    intervals: [],
    currentInterval: null,
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
    // Which recognition path the active (or most recent) session used. The
    // meter always tries 'on-device' first and may transparently fall back
    // to 'cloud' if the pre-flight or `start()` fails. The user does not see
    // or choose this; it is purely an internal book-keeping aid for the
    // diagnostics log and for one-shot fallback on a runtime error.
    activeRecognitionPath: null,
    cloudFallbackAttempted: false,
    tickHandle: null,
    restartTimer: null,
    wakeLock: null,
    keepAwake: false
  });

  const session = createSession();

  // ---------- Persistence ----------
  // Stats are written to localStorage on every meaningful state change so a
  // backgrounded tab, a screen lock, or even an aggressive mobile OS unloading
  // the page does not cost the user any progress. Storage access is wrapped
  // in `typeof` checks plus try/catch so the meter still works in private
  // mode, in iframes with storage disabled, or in sandboxed test contexts.

  const safeLocalStorage = () => {
    try {
      return typeof localStorage !== 'undefined' ? localStorage : null;
    } catch (_unused) {
      return null;
    }
  };

  const sanitizeNumber = (value, fallback) => {
    const numeric = Number(value);
    return isFinite(numeric) ? numeric : fallback;
  };

  const sanitizeWordEvents = (raw) => {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((event) => ({
        timestamp: sanitizeNumber(event && event.timestamp, NaN),
        wordCount: sanitizeNumber(event && event.wordCount, 0)
      }))
      .filter((event) => isFinite(event.timestamp) && event.wordCount > 0);
  };

  const sanitizeIntervals = (raw) => {
    if (!Array.isArray(raw)) return [];
    return raw
      .map((interval) => ({
        startedAt: sanitizeNumber(interval && interval.startedAt, NaN),
        endedAt: sanitizeNumber(interval && interval.endedAt, NaN),
        words: Math.max(0, Math.floor(sanitizeNumber(interval && interval.words, 0)))
      }))
      .filter((interval) =>
        isFinite(interval.startedAt)
        && isFinite(interval.endedAt)
        && interval.endedAt >= interval.startedAt);
  };

  const persistState = () => {
    const storage = safeLocalStorage();
    if (!storage) return;
    try {
      const snapshot = {
        version: 1,
        totalWords: session.totalWords,
        firstStartedAt: session.firstStartedAt,
        wordEvents: session.wordEvents,
        intervals: session.intervals
      };
      storage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
    } catch (_unused) { /* quota exceeded or serialization failure — drop silently */ }
  };

  const clearPersistedState = () => {
    const storage = safeLocalStorage();
    if (!storage) return;
    try { storage.removeItem(STORAGE_KEY); } catch (_unused) { /* noop */ }
  };

  const loadPersistedState = () => {
    const storage = safeLocalStorage();
    if (!storage) return null;
    try {
      const raw = storage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      if (!data || data.version !== 1) return null;
      return {
        totalWords: Math.max(0, Math.floor(sanitizeNumber(data.totalWords, 0))),
        firstStartedAt: isFinite(data.firstStartedAt) ? data.firstStartedAt : null,
        wordEvents: sanitizeWordEvents(data.wordEvents),
        intervals: sanitizeIntervals(data.intervals)
      };
    } catch (_unused) {
      return null;
    }
  };

  const restoreSessionFromStorage = () => {
    const persisted = loadPersistedState();
    if (!persisted) return false;
    const hasData = persisted.totalWords > 0 || persisted.intervals.length > 0;
    if (!hasData) return false;
    session.totalWords = persisted.totalWords;
    session.firstStartedAt = persisted.firstStartedAt;
    session.wordEvents = persisted.wordEvents;
    session.intervals = persisted.intervals;
    return true;
  };

  // Total *active* listening duration across all intervals, including the
  // open one if listening. Used as the elapsed denominator for the overall
  // rate so paused time does not artificially deflate words-per-minute.
  const computeActiveListeningMilliseconds = (now) => {
    const completed = session.intervals.reduce(
      (sum, interval) => sum + Math.max(0, interval.endedAt - interval.startedAt),
      0
    );
    const open = session.currentInterval
      ? Math.max(0, now - session.currentInterval.startedAt)
      : 0;
    return completed + open;
  };

  // Total wall-clock span between the very first start and now (or the last
  // recorded interval end if currently idle). Drives the trailing-window
  // rate denominators so a fresh session does not over-claim wpm.
  const computeWallClockSpanMilliseconds = (now) => {
    if (!session.firstStartedAt) return 0;
    const endpoint = session.listening
      ? now
      : session.intervals.length
        ? session.intervals[session.intervals.length - 1].endedAt
        : now;
    return Math.max(0, endpoint - session.firstStartedAt);
  };

  const addWordsToCurrentInterval = (count, timestamp) => {
    if (count <= 0) return;
    session.totalWords += count;
    session.wordEvents.push({ timestamp, wordCount: count });
    if (session.currentInterval) session.currentInterval.words += count;
  };

  const startSafely = (recognition) => {
    try {
      recognition.start();
      recordDiagnostic('recognition.start() invoked');
    } catch (err) {
      const message = (err && err.message) || String(err);
      recordDiagnostic('recognition.start() threw', { name: err && err.name, message });
      if (!/already started/i.test(message)) {
        showError(`Could not start recognition: ${message}`);
      }
    }
  };

  const beginListening = () => {
    const RecognitionConstructor = getRecognitionConstructor();
    if (!RecognitionConstructor) {
      recordDiagnostic('beginListening aborted — no SpeechRecognition constructor');
      showUnsupported();
      return;
    }

    const startedAt = Date.now();
    session.listening = true;
    session.startedAt = startedAt;
    if (!session.firstStartedAt) session.firstStartedAt = startedAt;
    session.currentInterval = { startedAt, words: 0 };
    session.captionEntries = [];
    session.finalIndex = 0;
    session.lastFinalTranscript = '';
    session.activeRecognitionPath = null;
    session.cloudFallbackAttempted = false;
    session.keepAwake = keepAwakeRequested();

    const locale = navigator.language || 'en-US';
    recordDiagnostic('beginListening', { locale, keepAwake: session.keepAwake });

    showError('');
    setKeepAwakeEnabled(false);
    setButtonStop();
    setStatus('listening');
    renderInitialMeta();
    renderTimeline();
    session.tickHandle = setInterval(handleTick, TICK_INTERVAL_MILLISECONDS);

    if (session.keepAwake) requestWakeLock();

    persistState();

    return attemptStart(RecognitionConstructor, locale);
  };

  // Wires up a fresh recognition object for the given path ('on-device' or
  // 'cloud'), installs the event handlers, stores it on the session, and
  // returns it. Splitting this out lets the cloud-fallback path build a
  // second recognition object without duplicating any wiring.
  const buildAndWireRecognition = (RecognitionConstructor, path, locale) => {
    const processLocally = path === RECOGNITION_PATHS.onDevice;
    const recognition = configureRecognition(new RecognitionConstructor(), processLocally, locale);
    recognition.onresult = handleResult;
    recognition.onerror = handleError;
    recognition.onend = handleEnd;
    session.recognition = recognition;
    session.activeRecognitionPath = path;
    return recognition;
  };

  // Main entry into the recognition layer. Always tries on-device first when
  // the browser exposes the static API; falls back to cloud transparently on
  // any signal (unavailable / install-failed / unknown). On the cloud path,
  // or on browsers without the static API, `start()` is invoked directly.
  const attemptStart = (RecognitionConstructor, locale) => {
    if (!ON_DEVICE_PREFLIGHT_ENABLED || !supportsOnDeviceLanguagePackApi(RecognitionConstructor)) {
      const recognition = buildAndWireRecognition(RecognitionConstructor, RECOGNITION_PATHS.cloud, locale);
      startSafely(recognition);
      return Promise.resolve();
    }
    const recognition = buildAndWireRecognition(RecognitionConstructor, RECOGNITION_PATHS.onDevice, locale);
    return ensureOnDeviceLanguagePack(RecognitionConstructor, locale, () => {
      if (session.listening && session.recognition === recognition) {
        setStatus('downloading on-device language pack…');
      }
    }).then((result) => {
      // The user may have hit Stop, or a new session may have started while
      // we were waiting on the install. In either case the original
      // recognition object is no longer the one to act on.
      if (!session.listening || session.recognition !== recognition) return;
      if (result === 'available') {
        setStatus('listening');
        startSafely(recognition);
        return;
      }
      // Anything else — 'unavailable', 'install-failed', or 'unknown' — means
      // the on-device path is not viable right now. Silently fall back to
      // cloud, which is exactly what Samsung Internet and every older
      // Chromium build effectively do already.
      recordDiagnostic('on-device pre-flight non-viable — falling back to cloud', { result });
      session.cloudFallbackAttempted = true;
      const cloudRecognition = buildAndWireRecognition(RecognitionConstructor, RECOGNITION_PATHS.cloud, locale);
      setStatus('listening');
      startSafely(cloudRecognition);
    });
  };

  const finalizeCurrentInterval = (now) => {
    if (!session.currentInterval) return;
    const interval = {
      startedAt: session.currentInterval.startedAt,
      endedAt: Math.max(now, session.currentInterval.startedAt),
      words: session.currentInterval.words
    };
    session.intervals.push(interval);
    session.currentInterval = null;
  };

  const endListening = (statusText = 'idle') => {
    const wasListening = session.listening;
    session.listening = false;
    finalizeCurrentInterval(Date.now());
    session.startedAt = null;
    if (session.recognition) {
      session.recognition.onresult = null;
      session.recognition.onerror = null;
      session.recognition.onend = null;
      try { session.recognition.stop(); } catch (_unused) { /* noop */ }
      session.recognition = null;
    }
    if (session.tickHandle) { clearInterval(session.tickHandle); session.tickHandle = null; }
    if (session.restartTimer) { clearTimeout(session.restartTimer); session.restartTimer = null; }
    releaseWakeLock();
    setButtonStart();
    setStatus(statusText);
    setKeepAwakeEnabled(true);
    if (wasListening) {
      persistState();
      renderTimeline();
      renderStartedRelative();
    }
  };

  const toggleListening = () => {
    if (session.listening) endListening('idle');
    else beginListening();
  };

  // ---------- Reset ----------
  // The reset button is the only way for the user to deliberately discard
  // accumulated stats. We confirm before destroying anything because the
  // explicit goal of persistence is to never silently lose progress.

  const resetAllStats = ({ skipConfirmation = false } = {}) => {
    if (!skipConfirmation && typeof window !== 'undefined' && typeof window.confirm === 'function') {
      if (!window.confirm(RESET_CONFIRMATION_PROMPT)) return false;
    }
    if (session.listening) endListening('idle');
    session.totalWords = 0;
    session.firstStartedAt = null;
    session.wordEvents = [];
    session.intervals = [];
    session.currentInterval = null;
    session.captionEntries = [];
    session.finalIndex = 0;
    session.lastFinalTranscript = '';
    clearPersistedState();
    setStatus('idle');
    showError('');
    renderCount();
    renderRates();
    renderCaptions();
    renderStartedRelative();
    renderTimeline();
    return true;
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
      addWordsToCurrentInterval(delta, now);
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
    addWordsToCurrentInterval(wordCount, now);
    session.captionEntries.push({ timestamp: now, text: transcript });
  };

  const handleResult = (event) => {
    const now = Date.now();
    let integratedAny = false;
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
      integratedAny = true;
    }
    pruneOldEntries(now);
    renderCount();
    renderRates();
    renderCaptions();
    if (integratedAny) {
      renderTimeline();
      persistState();
    }
  };

  const handleError = (event) => {
    const code = event && event.error;
    const message = event && event.message;
    recordDiagnostic('recognition.onerror', { code: code || '(none)', message: message || '' });
    if (isTransientErrorCode(code)) return;
    if (isPermissionDeniedCode(code)) {
      showError('Microphone permission denied. Allow microphone access and try again.');
      endListening('permission denied');
      return;
    }
    if (code === 'network') {
      showError('Network error reaching the speech service. Check your connection and try again.');
      return;
    }
    if (code === 'language-not-supported') {
      // The on-device pre-flight should have caught this, but some browsers
      // expose the static API and still reject `start()` at runtime. Retry
      // exactly once on the cloud path before giving up.
      if (session.listening && !session.cloudFallbackAttempted) {
        const RecognitionConstructor = getRecognitionConstructor();
        const locale = navigator.language || 'en-US';
        recordDiagnostic('language-not-supported at runtime — falling back to cloud', { locale });
        session.cloudFallbackAttempted = true;
        // Detach handlers from the failed recognition object before swapping.
        if (session.recognition) {
          session.recognition.onresult = null;
          session.recognition.onerror = null;
          session.recognition.onend = null;
          try { session.recognition.stop(); } catch (_unused) { /* noop */ }
        }
        if (RecognitionConstructor) {
          const cloudRecognition = buildAndWireRecognition(RecognitionConstructor, RECOGNITION_PATHS.cloud, locale);
          startSafely(cloudRecognition);
          return;
        }
      }
      showError('Speech recognition is not available for your language in this browser.');
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
    renderTimeline();
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
    const wallSpan = Math.max(1, computeWallClockSpanMilliseconds(now));
    const activeSpan = Math.max(1, computeActiveListeningMilliseconds(now));
    const shortWords = wordsInTrailingWindow(session.wordEvents, SHORT_RATE_WINDOW_MILLISECONDS, now);
    const longWords = wordsInTrailingWindow(session.wordEvents, LONG_RATE_WINDOW_MILLISECONDS, now);
    const shortElapsed = Math.min(SHORT_RATE_WINDOW_MILLISECONDS, wallSpan);
    const longElapsed = Math.min(LONG_RATE_WINDOW_MILLISECONDS, wallSpan);
    setText(ELEMENT_IDS.rateShort, formatRate(ratePerMinute(shortWords, shortElapsed)));
    setText(ELEMENT_IDS.rateLong, formatRate(ratePerMinute(longWords, longElapsed)));
    // Overall WPM uses *active* listening time so paused gaps don't dilute it.
    setText(ELEMENT_IDS.rateOverall, formatRate(ratePerMinute(session.totalWords, activeSpan)));
  };

  // The per-caption fade is bucketed into discrete classes so the only CSS
  // operation the application performs is applying a class. Five buckets
  // approximate the continuous `1 - age/CAPTION_WINDOW` curve clamped to
  // `MINIMUM_CAPTION_OPACITY`, which is visually indistinguishable from the
  // continuous version at the recognizer's update cadence.
  const CAPTION_FADE_BUCKETS = 5;

  const captionFadeBucket = (ageMilliseconds) => {
    const fraction = Math.max(0, ageMilliseconds) / CAPTION_WINDOW_MILLISECONDS;
    const bucket = Math.floor(fraction * CAPTION_FADE_BUCKETS);
    if (bucket < 0) return 0;
    if (bucket >= CAPTION_FADE_BUCKETS) return CAPTION_FADE_BUCKETS - 1;
    return bucket;
  };

  const renderCaptions = () => {
    if (!session.captionEntries.length) {
      setHtml(ELEMENT_IDS.captions, `<span class="wm-captions-placeholder">Waiting for speech…</span>`);
      return;
    }
    const now = Date.now();
    const captionsHtml = session.captionEntries
      .map((entry) => {
        const bucket = captionFadeBucket(now - entry.timestamp);
        return `<span class="wm-caption wm-caption-fade-${bucket}">${escapeHtml(entry.text)}</span>`;
      })
      .join(' ');
    setHtml(ELEMENT_IDS.captions, captionsHtml);
  };

  const renderStartedRelative = () => {
    if (!session.firstStartedAt) {
      setText(ELEMENT_IDS.started, '—');
      return;
    }
    const now = Date.now();
    const ageSeconds = Math.max(0, Math.floor((now - session.firstStartedAt) / MILLISECONDS_PER_SECOND));
    const clockText = formatClockTime(new Date(session.firstStartedAt));
    const relativeText = formatDuration(ageSeconds);
    const suffix = session.listening ? '' : ' · paused';
    setText(ELEMENT_IDS.started, `${clockText} · ${relativeText} ago${suffix}`);
  };

  const renderInitialMeta = () => {
    renderStartedRelative();
    renderCount();
    renderRates();
    renderCaptions();
  };

  const formatTimelineRow = (interval, isOpen, now) => {
    const startClock = formatClockTime(new Date(interval.startedAt));
    const endpoint = isOpen ? now : interval.endedAt;
    const endClock = isOpen ? '…' : formatClockTime(new Date(endpoint));
    const durationSeconds = Math.max(0, Math.floor((endpoint - interval.startedAt) / MILLISECONDS_PER_SECOND));
    const durationText = formatDuration(durationSeconds);
    const words = isOpen
      ? (session.currentInterval ? session.currentInterval.words : 0)
      : interval.words;
    const elapsedMs = Math.max(1, endpoint - interval.startedAt);
    const wpm = formatRate(ratePerMinute(words, elapsedMs));
    const liveTag = isOpen
      ? `<span class="wm-timeline-row-live">● live</span>`
      : '';
    return `<div class="wm-timeline-row">`
      + `<span class="wm-timeline-row-time">${escapeHtml(startClock)} → ${escapeHtml(endClock)}${liveTag}</span>`
      + `<span class="wm-timeline-row-duration">${escapeHtml(durationText)}</span>`
      + `<span class="wm-timeline-row-words">${words} w</span>`
      + `<span class="wm-timeline-row-rate">${wpm} wpm</span>`
      + `</div>`;
  };

  const renderTimeline = () => {
    const node = byId(ELEMENT_IDS.timeline);
    if (!node) return;
    const now = Date.now();
    const completed = session.intervals.slice();
    const ordered = completed.reverse(); // newest first
    const rows = [];
    if (session.currentInterval) {
      rows.push(formatTimelineRow(session.currentInterval, true, now));
    }
    ordered.slice(0, TIMELINE_MAX_RENDERED_ENTRIES).forEach((interval) => {
      rows.push(formatTimelineRow(interval, false, now));
    });
    if (!rows.length) {
      setHtml(ELEMENT_IDS.timeline, `<div id="${ELEMENT_IDS.timelineEmpty}" class="wm-timeline-empty">No intervals yet — press Start counting to begin.</div>`);
      return;
    }
    setHtml(ELEMENT_IDS.timeline, rows.join(''));
  };

  // ---------- UI state setters ----------

  const setStatus = (text) => setText(ELEMENT_IDS.status, text);

  const showError = (text) => {
    const node = byId(ELEMENT_IDS.error);
    if (node) node.textContent = text || '';
  };

  const setButtonListening = (listening) => {
    const button = byId(ELEMENT_IDS.button);
    if (!button) return;
    button.textContent = listening ? 'Stop counting' : 'Start counting';
    if (button.classList) {
      button.classList.toggle('wm-button-pill-stop', listening);
      button.classList.toggle('wm-button-pill-start', !listening);
    }
  };

  const setButtonStart = () => setButtonListening(false);
  const setButtonStop = () => setButtonListening(true);

  const setKeepAwakeEnabled = (enabled) => {
    const input = byId(ELEMENT_IDS.keepAwake);
    if (input) {
      input.disabled = !enabled;
      const label = input.parentElement;
      if (label && label.classList) {
        label.classList.toggle('wm-keep-awake-label-disabled', !enabled);
      }
    }
  };

  const showUnsupported = () => {
    showError('Your browser does not support the Web Speech API. Try Chrome, Edge, or Safari.');
    const button = byId(ELEMENT_IDS.button);
    if (button) {
      button.disabled = true;
      if (button.classList) button.classList.add('wm-button-pill-unsupported');
    }
    setKeepAwakeEnabled(false);
    setStatus('unsupported');
  };

  // ---------- Bootstrapping ----------

  const handlePageHide = () => persistState();

  const init = () => {
    const host = byId(HOST_ELEMENT_ID);
    if (!host) return () => {};
    ensureStylesheetLinked();
    host.innerHTML = '';
    host.appendChild(buildPanel());

    captureEnvironmentSnapshot();
    recordDiagnostic('init', { version: WORD_METER_VERSION });

    if (!getRecognitionConstructor()) {
      showUnsupported();
      return cleanup;
    }

    const restored = restoreSessionFromStorage();
    if (restored) {
      pruneOldEntries(Date.now());
      renderInitialMeta();
      renderTimeline();
      setStatus('idle · stats restored');
    } else {
      renderInitialMeta();
      renderTimeline();
    }

    const button = byId(ELEMENT_IDS.button);
    if (button) button.addEventListener('click', toggleListening);
    const resetButton = byId(ELEMENT_IDS.resetButton);
    if (resetButton) resetButton.addEventListener('click', () => resetAllStats());
    const copyButton = byId(ELEMENT_IDS.diagnosticsCopy);
    if (copyButton) copyButton.addEventListener('click', () => copyDiagnostics());
    if (typeof document !== 'undefined' && document.addEventListener) {
      document.addEventListener('visibilitychange', handleVisibilityChange);
      document.addEventListener('visibilitychange', persistOnHidden);
    }
    if (typeof window !== 'undefined' && window.addEventListener) {
      window.addEventListener('pagehide', handlePageHide);
      window.addEventListener('beforeunload', handlePageHide);
    }
    return cleanup;
  };

  const persistOnHidden = () => {
    if (typeof document === 'undefined') return;
    if (document.visibilityState === 'hidden') persistState();
  };

  const cleanup = () => {
    if (session.listening) endListening('idle');
    if (session.tickHandle) { clearInterval(session.tickHandle); session.tickHandle = null; }
    if (session.restartTimer) { clearTimeout(session.restartTimer); session.restartTimer = null; }
    releaseWakeLock();
    persistState();
    if (typeof document !== 'undefined' && document.removeEventListener) {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      document.removeEventListener('visibilitychange', persistOnHidden);
    }
    if (typeof window !== 'undefined' && window.removeEventListener) {
      window.removeEventListener('pagehide', handlePageHide);
      window.removeEventListener('beforeunload', handlePageHide);
    }
  };

  // Test hook — only exposed when explicitly enabled before the script runs.
  if (window.__WM_TEST_HOOK__) {
    window.__wordMeter = {
      getState: () => ({
        listening: session.listening,
        totalWords: session.totalWords,
        captions: session.captionEntries.map((entry) => entry.text),
        startedAt: session.startedAt,
        firstStartedAt: session.firstStartedAt,
        intervals: session.intervals.map((interval) => ({ ...interval })),
        currentInterval: session.currentInterval ? { ...session.currentInterval } : null,
        activeRecognitionPath: session.activeRecognitionPath,
        cloudFallbackAttempted: session.cloudFallbackAttempted,
        keepAwake: session.keepAwake,
        wakeLockHeld: session.wakeLock !== null,
        version: WORD_METER_VERSION,
        diagnosticsEntries: diagnostics.entries.map((entry) => ({ ...entry })),
        diagnosticsSnapshot: diagnostics.snapshot ? { ...diagnostics.snapshot } : null
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
      start: () => beginListening(),
      stop: () => endListening('idle'),
      reset: () => resetAllStats({ skipConfirmation: true }),
      persistNow: () => persistState(),
      copyDiagnostics: () => copyDiagnostics(),
      getDiagnosticsText: () => formatDiagnostics(),
      simulateError: (errorCode, message) => handleError({ error: errorCode, message: message || '' }),
      reload: () => {
        // Mimics a fresh page load by clearing in-memory session and loading
        // from storage. Used by tests to verify round-trip persistence.
        session.listening = false;
        session.startedAt = null;
        session.firstStartedAt = null;
        session.intervals = [];
        session.currentInterval = null;
        session.totalWords = 0;
        session.wordEvents = [];
        session.captionEntries = [];
        session.finalIndex = 0;
        session.lastFinalTranscript = '';
        return restoreSessionFromStorage();
      }
    };
  }

  let activeCleanup = init();
  document.addEventListener('nav', () => {
    if (activeCleanup) activeCleanup();
    activeCleanup = init();
  });
}();
