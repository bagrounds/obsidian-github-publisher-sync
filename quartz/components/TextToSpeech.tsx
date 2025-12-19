// @ts-ignore
import textToSpeechScript from "./scripts/texttospeech.inline"
import styles from "./styles/texttospeech.scss"
import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { classNames } from "../util/lang"

const TextToSpeech: QuartzComponent = ({ displayClass }: QuartzComponentProps) => {
  return (
    <button class={classNames(displayClass, "text-to-speech")} title="Read aloud">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        xmlnsXlink="http://www.w3.org/1999/xlink"
        version="1.1"
        class="tts-icon"
        x="0px"
        y="0px"
        viewBox="0 0 24 24"
        style="enable-background:new 0 0 24 24"
        xmlSpace="preserve"
        aria-label="Read aloud"
      >
        <title>Read aloud</title>
        <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"></path>
      </svg>
    </button>
  )
}

TextToSpeech.beforeDOMLoaded = textToSpeechScript
TextToSpeech.css = styles

export default (() => TextToSpeech) satisfies QuartzComponentConstructor
