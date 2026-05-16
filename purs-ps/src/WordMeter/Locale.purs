-- | A validated BCP 47 locale tag used throughout the recognition
-- | pipeline. Wrapping the raw `String` from `navigator.language` in
-- | this newtype prevents accidentally mixing locale tags with
-- | unrelated strings such as diagnostic labels.
module WordMeter.Locale (Locale(..), renderLocale) where

import Prelude

-- | An opaque BCP 47 locale tag (for example @"en-US"@, @"fr-FR"@,
-- | @"zh-Hant"@). Produced by `WordMeter.Main.sessionLocale` from
-- | `EnvironmentSnapshot.navigatorLanguage` and consumed by the
-- | recognition capability at start-time.
newtype Locale = Locale String

derive newtype instance eqLocale :: Eq Locale

-- | Unwrap a `Locale` to its underlying BCP 47 string for FFI
-- | boundaries and diagnostic log lines.
renderLocale :: Locale -> String
renderLocale (Locale locale) = locale
