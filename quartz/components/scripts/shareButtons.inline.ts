const handleCopyLink = async (button: HTMLButtonElement, url: string): Promise<void> => {
  try {
    await navigator.clipboard.writeText(url)
    button.classList.add("copy-success")
    const originalText = button.textContent
    button.textContent = "✅ Copied!"
    setTimeout(() => {
      button.textContent = originalText
      button.classList.remove("copy-success")
    }, 2000)
  } catch {
    prompt("Copy this link:", url)
  }
}

const handleNativeShare = async (title: string, url: string, text: string): Promise<void> => {
  try {
    await navigator.share({ title, url, text })
  } catch (error: unknown) {
    if (error instanceof Error && error.name !== "AbortError") {
      console.error("Share failed:", error)
    }
  }
}

document.addEventListener("nav", () => {
  const containers = document.querySelectorAll<HTMLDivElement>(".share-buttons")

  for (const container of containers) {
    const url = container.dataset.url ?? ""
    const title = container.dataset.title ?? ""
    const shareText = container.dataset.shareText ?? ""

    const copyButtons = container.querySelectorAll<HTMLButtonElement>(".share-copy-link")
    for (const button of copyButtons) {
      const copyLinkClickHandler = () => { void handleCopyLink(button, url) }
      button.addEventListener("click", copyLinkClickHandler)
      window.addCleanup(() => button.removeEventListener("click", copyLinkClickHandler))
    }

    const nativeButtons = container.querySelectorAll<HTMLButtonElement>(".share-native")
    for (const button of nativeButtons) {
      if (navigator.share) {
        button.classList.add("share-native-visible")
        const nativeShareClickHandler = () => { void handleNativeShare(title, url, shareText) }
        button.addEventListener("click", nativeShareClickHandler)
        window.addCleanup(() => button.removeEventListener("click", nativeShareClickHandler))
      }
    }
  }
})
