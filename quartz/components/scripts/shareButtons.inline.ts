const MASTODON_INSTANCE_KEY = "share-mastodon-instance"

const isValidInstance = (instance: string): boolean => {
  const trimmed = instance.trim()
  return trimmed.length > 0 && trimmed.includes(".") && !trimmed.includes(" ")
}

const normalizeMastodonInstance = (raw: string): string => {
  const trimmed = raw.trim().toLowerCase()
  return trimmed.replace(/^https?:\/\//, "").replace(/\/+$/, "")
}

const getMastodonShareUrl = (instance: string, text: string): string =>
  `https://${instance}/share?text=${encodeURIComponent(text)}`

const handleMastodonShare = (shareText: string, forcePrompt: boolean): void => {
  const saved = localStorage.getItem(MASTODON_INSTANCE_KEY)

  if (saved && !forcePrompt) {
    window.open(getMastodonShareUrl(saved, shareText), "_blank", "noopener,noreferrer")
    return
  }

  const promptMessage = saved
    ? `Enter your Mastodon instance (current: ${saved}):`
    : "Enter your Mastodon instance (e.g. mastodon.social):"

  const input = prompt(promptMessage, saved ?? "")

  if (!input) return

  const instance = normalizeMastodonInstance(input)

  if (!isValidInstance(instance)) {
    alert("That doesn't look like a valid Mastodon instance domain. Please try again.")
    return
  }

  localStorage.setItem(MASTODON_INSTANCE_KEY, instance)
  window.open(getMastodonShareUrl(instance, shareText), "_blank", "noopener,noreferrer")
}

document.addEventListener("nav", () => {
  const mastodonButtons = document.querySelectorAll<HTMLButtonElement>(".share-mastodon")

  for (const button of mastodonButtons) {
    const clickHandler = (event: MouseEvent) => {
      const shareText = button.dataset.shareText ?? ""
      const forcePrompt = event.shiftKey
      handleMastodonShare(shareText, forcePrompt)
    }

    button.addEventListener("click", clickHandler)
    window.addCleanup(() => button.removeEventListener("click", clickHandler))
  }
})
