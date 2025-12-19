// Text-to-speech functionality using the Web Speech API
// This is a free and open source solution built into modern browsers

let currentUtterance: SpeechSynthesisUtterance | null = null
let isReading = false

document.addEventListener("nav", () => {
  const speakText = () => {
    // Check if speech synthesis is supported
    if (!("speechSynthesis" in window)) {
      alert("Sorry, your browser doesn't support text-to-speech!")
      return
    }

    const button = document.querySelector(".text-to-speech") as HTMLElement
    
    if (isReading) {
      // Stop reading
      window.speechSynthesis.cancel()
      isReading = false
      button?.classList.remove("speaking")
      return
    }

    // Get the main content text
    const article = document.querySelector("article")
    if (!article) {
      alert("No content found to read!")
      return
    }

    // Extract text content, excluding code blocks and other non-readable elements
    const clonedArticle = article.cloneNode(true) as HTMLElement
    
    // Remove elements that shouldn't be read
    const elementsToRemove = clonedArticle.querySelectorAll(
      "pre, code, script, style, .giscus, .backlinks, button, nav"
    )
    elementsToRemove.forEach((el) => el.remove())

    const textContent = clonedArticle.innerText.trim()

    if (!textContent) {
      alert("No readable content found!")
      return
    }

    // Create utterance
    currentUtterance = new SpeechSynthesisUtterance(textContent)
    
    // Configure utterance
    currentUtterance.rate = 1.0 // Normal speed
    currentUtterance.pitch = 1.0 // Normal pitch
    currentUtterance.volume = 1.0 // Full volume

    // Handle events
    currentUtterance.onstart = () => {
      isReading = true
      button?.classList.add("speaking")
    }

    currentUtterance.onend = () => {
      isReading = false
      button?.classList.remove("speaking")
      currentUtterance = null
    }

    currentUtterance.onerror = (event) => {
      console.error("Speech synthesis error:", event)
      isReading = false
      button?.classList.remove("speaking")
      currentUtterance = null
    }

    // Start speaking
    window.speechSynthesis.speak(currentUtterance)
  }

  // Add click listener to TTS button
  for (const ttsButton of document.getElementsByClassName("text-to-speech")) {
    ttsButton.addEventListener("click", speakText)
    window.addCleanup(() => {
      ttsButton.removeEventListener("click", speakText)
      // Cancel any ongoing speech when cleaning up
      if (isReading) {
        window.speechSynthesis.cancel()
        isReading = false
      }
    })
  }
})
