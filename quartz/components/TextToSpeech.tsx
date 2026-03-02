import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
// @ts-ignore
import ttsScript from "./scripts/tts.inline"
import ttsStyle from "./styles/tts.scss"

const TextToSpeech: QuartzComponent = ({ displayClass }: QuartzComponentProps) => {
  return (
    <div class={`tts-container ${displayClass ?? ""}`} id="tts-container">
      <div class="tts-controls">
        <button class="tts-btn" id="tts-back" aria-label="Skip back 30 seconds" title="Back 30s">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
            <path d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z" />
            <text x="12" y="15.5" text-anchor="middle" font-size="7" font-weight="bold">30</text>
          </svg>
        </button>
        <button class="tts-btn tts-play-btn" id="tts-play" aria-label="Play" title="Play">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor" id="tts-play-icon">
            <path d="M8 5v14l11-7z" />
          </svg>
          <svg
            viewBox="0 0 24 24"
            width="22"
            height="22"
            fill="currentColor"
            id="tts-pause-icon"
            style="display:none"
          >
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
          </svg>
        </button>
        <button
          class="tts-btn"
          id="tts-forward"
          aria-label="Skip forward 30 seconds"
          title="Forward 30s"
        >
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
            <path d="M12 5V1l5 5-5 5V7c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6h2c0 4.42-3.58 8-8 8s-8-3.58-8-8 3.58-8 8-8z" />
            <text x="12" y="15.5" text-anchor="middle" font-size="7" font-weight="bold">30</text>
          </svg>
        </button>
        <select id="tts-speed" class="tts-speed" aria-label="Playback speed" title="Speed">
          <option value="0.5">0.5×</option>
          <option value="0.75">0.75×</option>
          <option value="1" selected>1×</option>
          <option value="1.25">1.25×</option>
          <option value="1.5">1.5×</option>
          <option value="1.75">1.75×</option>
          <option value="2">2×</option>
        </select>
      </div>
      <div class="tts-seek-row">
        <span class="tts-time" id="tts-current-time">
          0:00
        </span>
        <input
          type="range"
          id="tts-seek"
          class="tts-seek"
          min="0"
          max="100"
          value="0"
          aria-label="Seek"
          title="Seek"
        />
        <span class="tts-time" id="tts-total-time">
          0:00
        </span>
      </div>
    </div>
  )
}

TextToSpeech.afterDOMLoaded = ttsScript
TextToSpeech.css = ttsStyle

export default (() => TextToSpeech) satisfies QuartzComponentConstructor
