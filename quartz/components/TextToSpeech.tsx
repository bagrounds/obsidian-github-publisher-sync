// @ts-ignore
import textToSpeechScript from "./scripts/texttospeech.inline"
import styles from "./styles/texttospeech.scss"
import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"

const TextToSpeech: QuartzComponent = ({ displayClass }: QuartzComponentProps) => {
  return (
    <div class={displayClass}>
      <div id="tts-player" class="tts-player collapsed">
        <button id="tts-toggle" class="tts-toggle-btn" title="Toggle audio player">
          <svg class="tts-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"></path>
          </svg>
        </button>
        
        <div class="tts-controls">
          <button id="tts-play-pause" class="tts-control-btn" title="Play/Pause">
            <svg class="play-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M8 5v14l11-7z"></path>
            </svg>
            <svg class="pause-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
              <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z"></path>
            </svg>
          </button>
          
          <div class="tts-progress-container">
            <input type="range" id="tts-progress" class="tts-progress" min="0" max="100" value="0" />
            <div class="tts-time">
              <span id="tts-current-time">0:00</span>
              <span id="tts-total-time">0:00</span>
            </div>
          </div>
          
          <div class="tts-speed-container">
            <label for="tts-speed">Speed:</label>
            <select id="tts-speed" class="tts-speed">
              <option value="0.5">0.5x</option>
              <option value="0.75">0.75x</option>
              <option value="1" selected>1x</option>
              <option value="1.25">1.25x</option>
              <option value="1.5">1.5x</option>
              <option value="1.75">1.75x</option>
              <option value="2">2x</option>
            </select>
          </div>
        </div>
      </div>
    </div>
  )
}

TextToSpeech.beforeDOMLoaded = textToSpeechScript
TextToSpeech.css = styles

export default (() => TextToSpeech) satisfies QuartzComponentConstructor
