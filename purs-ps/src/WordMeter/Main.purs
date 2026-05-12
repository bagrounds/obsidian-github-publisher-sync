-- | Entry point for the PureScript Word Meter bundle.
-- |
-- | This is the hello-world slice: when the page has a `#word-meter`
-- | host element, we replace its contents with a labelled placeholder
-- | that makes the PureScript build visually distinguishable from the
-- | legacy JavaScript build during side-by-side iteration. The element
-- | exposes stable `data-testid`s so the Playwright suite in
-- | `tests/e2e/` can target either implementation through the same
-- | selector contract.
module WordMeter.Main where

import Prelude

import Effect (Effect)
import WordMeter.FFI (Maybe(..), getElementById, setInnerHtml)
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

placeholderHtml :: String
placeholderHtml =
  "<div data-testid=\"wm-root\" style=\"font-family:system-ui,-apple-system,sans-serif;padding:16px;border-radius:12px;background:#0b1220;color:#e6edf3;\">"
    <> "<div data-testid=\"wm-impl\" style=\"font-size:12px;letter-spacing:0.08em;text-transform:uppercase;color:#7aa2f7;\">PureScript build</div>"
    <> "<div data-testid=\"wm-count\" style=\"font-size:48px;font-variant-numeric:tabular-nums;margin:8px 0;\">0</div>"
    <> "<div data-testid=\"wm-count-label\" style=\"font-size:14px;color:#9aa5b1;\">words counted</div>"
    <> "<button data-testid=\"wm-toggle\" type=\"button\" disabled style=\"margin-top:12px;padding:8px 16px;border:0;border-radius:8px;background:#1f6feb;color:white;cursor:not-allowed;opacity:0.6;\">Start counting</button>"
    <> "<div data-testid=\"wm-version\" style=\"margin-top:12px;font-size:11px;color:#7d8590;\">Word Meter (PureScript) v"
    <> version
    <> "</div>"
    <> "</div>"

main :: Effect Unit
main = do
  hostMaybe <- getElementById hostElementId
  case hostMaybe of
    Nothing -> pure unit
    Just host -> setInnerHtml host placeholderHtml
