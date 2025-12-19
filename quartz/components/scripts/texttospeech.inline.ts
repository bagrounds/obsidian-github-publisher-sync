// Text-to-speech functionality using the Web Speech API
// This is a free and open source solution built into modern browsers

// State management
let currentUtterance: SpeechSynthesisUtterance | null = null
let isReading = false
let isPaused = false
let words: string[] = []
let currentWordIndex = 0
let currentSpeed = 1.0
let highlightedElements: HTMLElement[] = []

// Emoji regex pattern to filter out emojis
const emojiRegex = /[\u{1F300}-\u{1F9FF}\u{1F600}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F900}-\u{1F9FF}\u{1F1E0}-\u{1F1FF}]/gu

function removeEmojis(text: string): string {
  return text.replace(emojiRegex, '').replace(/\s+/g, ' ').trim()
}

function splitIntoWords(text: string): string[] {
  // Split by whitespace and punctuation, keeping the structure
  return text.split(/(\s+)/).filter(w => w.trim().length > 0)
}

function updateProgress() {
  const progress = document.getElementById('tts-progress') as HTMLInputElement
  if (progress && words.length > 0) {
    const percentage = (currentWordIndex / words.length) * 100
    progress.value = percentage.toString()
  }
}

function estimateTime(wordCount: number, speed: number): number {
  // Average speaking rate is ~150 words per minute at normal speed
  const wordsPerMinute = 150 * speed
  return (wordCount / wordsPerMinute) * 60
}

function updateTime() {
  const currentTimeEl = document.getElementById('tts-current-time')
  const totalTimeEl = document.getElementById('tts-total-time')
  
  if (currentTimeEl && totalTimeEl && words.length > 0) {
    const currentTime = estimateTime(currentWordIndex, currentSpeed)
    const totalTime = estimateTime(words.length, currentSpeed)
    
    const formatTime = (seconds: number) => {
      const mins = Math.floor(seconds / 60)
      const secs = Math.floor(seconds % 60)
      return `${mins}:${secs.toString().padStart(2, '0')}`
    }
    
    currentTimeEl.textContent = formatTime(currentTime)
    totalTimeEl.textContent = formatTime(totalTime)
  }
}

function clearHighlights() {
  highlightedElements.forEach(el => {
    el.style.backgroundColor = ''
    el.style.color = ''
  })
  highlightedElements = []
}

function highlightWord(wordIndex: number) {
  clearHighlights()
  
  if (wordIndex >= words.length) return
  
  const article = document.querySelector('article')
  if (!article) return
  
  // Find the word in the DOM
  const targetWord = words[wordIndex].trim().toLowerCase()
  if (!targetWord) return
  
  const walker = document.createTreeWalker(
    article,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode: (node) => {
        const parent = node.parentElement
        if (!parent) return NodeFilter.FILTER_REJECT
        
        // Skip non-readable elements
        const skipTags = ['CODE', 'PRE', 'SCRIPT', 'STYLE', 'BUTTON', 'NAV']
        if (skipTags.includes(parent.tagName)) return NodeFilter.FILTER_REJECT
        
        return NodeFilter.FILTER_ACCEPT
      }
    }
  )
  
  let currentWordCount = 0
  let node: Node | null
  
  while ((node = walker.nextNode())) {
    const text = node.textContent || ''
    const nodeWords = text.split(/\s+/).filter(w => w.trim().length > 0)
    
    if (currentWordCount + nodeWords.length > wordIndex) {
      // This node contains our target word
      const wordIndexInNode = wordIndex - currentWordCount
      const parent = node.parentElement
      
      if (parent) {
        parent.style.backgroundColor = 'var(--highlight)'
        parent.style.color = 'var(--dark)'
        highlightedElements.push(parent)
        
        // Scroll into view smoothly
        parent.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'nearest' })
      }
      break
    }
    
    currentWordCount += nodeWords.length
  }
}

function speakText() {
  if (!('speechSynthesis' in window)) {
    alert('Sorry, your browser doesn\'t support text-to-speech!')
    return
  }
  
  if (words.length === 0) return
  
  // Create the full text from remaining words
  const textToSpeak = words.slice(currentWordIndex).join(' ')
  
  if (!textToSpeak.trim()) {
    stopReading()
    return
  }
  
  currentUtterance = new SpeechSynthesisUtterance(textToSpeak)
  currentUtterance.rate = currentSpeed
  currentUtterance.pitch = 1.0
  currentUtterance.volume = 1.0
  
  // Track word boundaries for highlighting
  currentUtterance.onboundary = (event) => {
    if (event.name === 'word') {
      currentWordIndex = Math.min(
        words.length - 1,
        currentWordIndex + 1
      )
      highlightWord(currentWordIndex)
      updateProgress()
      updateTime()
    }
  }
  
  currentUtterance.onstart = () => {
    isReading = true
    isPaused = false
    highlightWord(currentWordIndex)
    updateProgress()
    updateTime()
    updatePlayerUI()
  }
  
  currentUtterance.onend = () => {
    stopReading()
  }
  
  currentUtterance.onpause = () => {
    isPaused = true
    updatePlayerUI()
  }
  
  currentUtterance.onresume = () => {
    isPaused = false
    updatePlayerUI()
  }
  
  currentUtterance.onerror = (event) => {
    console.error('Speech synthesis error:', event)
    // Don't stop on interrupted errors (these happen during speed changes)
    if (event.error !== 'interrupted') {
      stopReading()
    }
  }
  
  window.speechSynthesis.speak(currentUtterance)
  isReading = true
  updatePlayerUI()
}

function startReading() {
  // Cancel any existing speech
  window.speechSynthesis.cancel()
  
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
  
  words = splitIntoWords(textContent)
  currentWordIndex = 0
  
  speakText()
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
  currentWordIndex = 0
  words = []
  currentUtterance = null
  
  clearHighlights()
  updatePlayerUI()
  updateProgress()
  updateTime()
}

function changeSpeed(newSpeed: number) {
  currentSpeed = newSpeed
  
  if (isReading && !isPaused) {
    // Save current state
    const wasReading = isReading
    const currentIndex = currentWordIndex
    
    // Cancel current utterance
    window.speechSynthesis.cancel()
    
    // Resume from current position with new speed
    if (wasReading && currentIndex < words.length) {
      speakText()
    }
  }
}

function seekToPosition(percentage: number) {
  if (words.length === 0) return
  
  const newIndex = Math.floor((percentage / 100) * words.length)
  currentWordIndex = Math.max(0, Math.min(newIndex, words.length - 1))
  
  // Cancel current speech
  window.speechSynthesis.cancel()
  
  // If we were reading, continue from new position
  if (isReading) {
    speakText()
  } else {
    highlightWord(currentWordIndex)
    updateProgress()
    updateTime()
  }
}

function updatePlayerUI() {
  const player = document.getElementById('tts-player')
  const playPauseBtn = document.getElementById('tts-play-pause')
  
  if (player) {
    if (isReading || isPaused) {
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

// Event listeners
document.addEventListener('nav', () => {
  // Ensure any previous speech is stopped
  stopReading()
  
  // Toggle player visibility
  const toggleBtn = document.getElementById('tts-toggle')
  const toggleHandler = () => {
    const player = document.getElementById('tts-player')
    player?.classList.toggle('collapsed')
  }
  
  toggleBtn?.removeEventListener('click', toggleHandler)
  toggleBtn?.addEventListener('click', toggleHandler)
  
  // Play/Pause button
  const playPauseBtn = document.getElementById('tts-play-pause')
  const playPauseHandler = () => {
    if (!isReading && !isPaused) {
      startReading()
    } else if (isPaused) {
      resumeReading()
    } else {
      pauseReading()
    }
  }
  
  playPauseBtn?.removeEventListener('click', playPauseHandler)
  playPauseBtn?.addEventListener('click', playPauseHandler)
  
  // Speed control
  const speedSelect = document.getElementById('tts-speed') as HTMLSelectElement
  const speedHandler = (e: Event) => {
    const newSpeed = parseFloat((e.target as HTMLSelectElement).value)
    changeSpeed(newSpeed)
  }
  
  speedSelect?.removeEventListener('change', speedHandler)
  speedSelect?.addEventListener('change', speedHandler)
  
  // Progress slider - use 'change' event for seeking
  const progressInput = document.getElementById('tts-progress') as HTMLInputElement
  const progressHandler = (e: Event) => {
    const percentage = parseFloat((e.target as HTMLInputElement).value)
    seekToPosition(percentage)
  }
  
  progressInput?.removeEventListener('change', progressHandler)
  progressInput?.addEventListener('change', progressHandler)
  
  // Cleanup on navigation
  window.addCleanup(() => {
    stopReading()
  })
})

// Ensure speech stops when page is hidden or unloaded
window.addEventListener('pagehide', () => {
  stopReading()
})

window.addEventListener('beforeunload', () => {
  stopReading()
})
