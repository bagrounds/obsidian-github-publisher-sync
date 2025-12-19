// Text-to-speech functionality using the Web Speech API
// This is a free and open source solution built into modern browsers

let currentUtterance: SpeechSynthesisUtterance | null = null
let isReading = false
let isPaused = false
let sentences: string[] = []
let currentSentenceIndex = 0
let currentSpeed = 1.0
let highlightedElement: HTMLElement | null = null

// Emoji regex pattern to filter out emojis
const emojiRegex = /[\u{1F300}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}]/gu

function removeEmojis(text: string): string {
  return text.replace(emojiRegex, '').replace(/\s+/g, ' ').trim()
}

function splitIntoSentences(text: string): string[] {
  // Split by sentence-ending punctuation
  const raw = text.match(/[^.!?]+[.!?]+/g) || [text]
  return raw.map(s => s.trim()).filter(s => s.length > 0)
}

function updateProgress() {
  const progress = document.getElementById('tts-progress') as HTMLInputElement
  if (progress && sentences.length > 0) {
    const percentage = (currentSentenceIndex / sentences.length) * 100
    progress.value = percentage.toString()
  }
}

function updateTime() {
  const currentTimeEl = document.getElementById('tts-current-time')
  const totalTimeEl = document.getElementById('tts-total-time')
  
  if (currentTimeEl && totalTimeEl) {
    const currentMinutes = Math.floor(currentSentenceIndex / 2)
    const currentSeconds = (currentSentenceIndex % 2) * 30
    currentTimeEl.textContent = `${currentMinutes}:${currentSeconds.toString().padStart(2, '0')}`
    
    const totalMinutes = Math.floor(sentences.length / 2)
    const totalSeconds = (sentences.length % 2) * 30
    totalTimeEl.textContent = `${totalMinutes}:${totalSeconds.toString().padStart(2, '0')}`
  }
}

function highlightCurrentSentence() {
  // Remove previous highlight
  if (highlightedElement) {
    highlightedElement.style.backgroundColor = ''
    highlightedElement.style.color = ''
  }
  
  // Find and highlight current sentence in the article
  const article = document.querySelector('article')
  if (!article || currentSentenceIndex >= sentences.length) return
  
  const currentSentence = sentences[currentSentenceIndex]
  const walker = document.createTreeWalker(
    article,
    NodeFilter.SHOW_TEXT,
    null
  )
  
  let node: Node | null
  while ((node = walker.nextNode())) {
    const text = node.textContent || ''
    const cleanText = removeEmojis(text).trim()
    
    if (cleanText && currentSentence.includes(cleanText.substring(0, Math.min(20, cleanText.length)))) {
      const parent = node.parentElement
      if (parent && parent.tagName !== 'CODE' && parent.tagName !== 'PRE') {
        highlightedElement = parent
        parent.style.backgroundColor = 'var(--highlight)'
        parent.style.color = 'var(--dark)'
        parent.scrollIntoView({ behavior: 'smooth', block: 'center' })
        break
      }
    }
  }
}

function speakSentence(index: number) {
  if (index >= sentences.length) {
    stopReading()
    return
  }
  
  currentSentenceIndex = index
  const sentence = sentences[index]
  
  currentUtterance = new SpeechSynthesisUtterance(sentence)
  currentUtterance.rate = currentSpeed
  currentUtterance.pitch = 1.0
  currentUtterance.volume = 1.0
  
  currentUtterance.onstart = () => {
    highlightCurrentSentence()
    updateProgress()
    updateTime()
  }
  
  currentUtterance.onend = () => {
    speakSentence(index + 1)
  }
  
  currentUtterance.onerror = (event) => {
    console.error('Speech synthesis error:', event)
    stopReading()
  }
  
  window.speechSynthesis.speak(currentUtterance)
}

function startReading() {
  if (!('speechSynthesis' in window)) {
    alert('Sorry, your browser doesn\'t support text-to-speech!')
    return
  }
  
  const article = document.querySelector('article')
  if (!article) {
    alert('No content found to read!')
    return
  }
  
  // Extract text content, excluding code blocks and other non-readable elements
  const clonedArticle = article.cloneNode(true) as HTMLElement
  
  const elementsToRemove = clonedArticle.querySelectorAll(
    'pre, code, script, style, .giscus, .backlinks, button, nav, svg'
  )
  elementsToRemove.forEach((el) => el.remove())
  
  let textContent = clonedArticle.innerText.trim()
  
  // Remove emojis
  textContent = removeEmojis(textContent)
  
  if (!textContent) {
    alert('No readable content found!')
    return
  }
  
  sentences = splitIntoSentences(textContent)
  currentSentenceIndex = 0
  isReading = true
  isPaused = false
  
  updatePlayerUI()
  speakSentence(0)
}

function pauseReading() {
  if (isReading && !isPaused) {
    window.speechSynthesis.pause()
    isPaused = true
    updatePlayerUI()
  }
}

function resumeReading() {
  if (isReading && isPaused) {
    window.speechSynthesis.resume()
    isPaused = false
    updatePlayerUI()
  }
}

function stopReading() {
  window.speechSynthesis.cancel()
  isReading = false
  isPaused = false
  currentSentenceIndex = 0
  sentences = []
  
  if (highlightedElement) {
    highlightedElement.style.backgroundColor = ''
    highlightedElement.style.color = ''
    highlightedElement = null
  }
  
  updatePlayerUI()
  updateProgress()
  updateTime()
}

function updatePlayerUI() {
  const player = document.getElementById('tts-player')
  const playPauseBtn = document.getElementById('tts-play-pause')
  
  if (player) {
    if (isReading) {
      player.classList.add('playing')
      player.classList.remove('collapsed')
    } else {
      player.classList.remove('playing')
    }
  }
  
  if (playPauseBtn) {
    if (isReading && !isPaused) {
      playPauseBtn.classList.add('paused')
    } else {
      playPauseBtn.classList.remove('paused')
    }
  }
}

document.addEventListener('nav', () => {
  // Toggle player visibility
  const toggleBtn = document.getElementById('tts-toggle')
  toggleBtn?.addEventListener('click', () => {
    const player = document.getElementById('tts-player')
    player?.classList.toggle('collapsed')
  })
  
  // Play/Pause button
  const playPauseBtn = document.getElementById('tts-play-pause')
  playPauseBtn?.addEventListener('click', () => {
    if (!isReading) {
      startReading()
    } else if (isPaused) {
      resumeReading()
    } else {
      pauseReading()
    }
  })
  
  // Speed control
  const speedSelect = document.getElementById('tts-speed') as HTMLSelectElement
  speedSelect?.addEventListener('change', (e) => {
    currentSpeed = parseFloat((e.target as HTMLSelectElement).value)
    if (isReading && currentUtterance) {
      // Restart current sentence with new speed
      window.speechSynthesis.cancel()
      speakSentence(currentSentenceIndex)
    }
  })
  
  // Progress slider
  const progressInput = document.getElementById('tts-progress') as HTMLInputElement
  progressInput?.addEventListener('input', (e) => {
    const percentage = parseFloat((e.target as HTMLInputElement).value)
    const newIndex = Math.floor((percentage / 100) * sentences.length)
    
    if (isReading) {
      window.speechSynthesis.cancel()
      speakSentence(newIndex)
    }
  })
  
  // Cleanup
  window.addCleanup(() => {
    if (isReading) {
      stopReading()
    }
  })
})
