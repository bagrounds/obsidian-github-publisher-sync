module Automation.AiFiction
  ( fictionSectionHeader
  , defaultFictionModel
  , fictionModelPool
  , selectFictionModelChain
  , fictionEligibilityCutoff
  , stripForPrompt
  , reflectionNeedsFiction
  , buildFictionPrompt
  , parseFictionResponse
  , buildFictionSignature
  , applyFiction
  , generateFiction
  , FictionConfig (FictionConfig, models, noteContent)
  , FictionResult (FictionResult, fiction, model, updatedContent)
  ) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, LocalTime (..), TimeOfDay (..))
import Data.Time.Calendar (toModifiedJulianDay)

import Automation.Platform
  ( updatesSectionHeader
  )

import Automation.Text (stripCodeFences)
import qualified Automation.Gemini as Gemini
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

fictionSectionHeader :: Text
fictionSectionHeader = "## 🤖🐲 AI Fiction"

defaultFictionModel :: Gemini.Model
defaultFictionModel = Gemini.Gemini25Flash

-- | The pool of models rotated through for fiction generation, one per day,
-- so the quality and feel of different models can be compared over time.
-- Every model in the pool also acts as a fallback for every other model, so
-- a rate-limited or otherwise failing primary model still yields fiction.
fictionModelPool :: NonEmpty Gemini.Model
fictionModelPool =
  Gemini.Gemini25Flash :|
    [ Gemini.Gemini25FlashLite
    , Gemini.Gemini31FlashLite
    , Gemini.Gemini3Flash
    , Gemini.Gemini20Flash
    , Gemini.Gemma3
    ]

-- | Deterministically rotate the model pool by calendar day so each day picks
-- a different primary model, cycling through the whole pool. The full pool is
-- preserved as the fallback chain (primary first, then the rest), so on a
-- rate-limit or failure the generator falls back across all models until one
-- works. Because selection is a pure function of the day, re-runs for the same
-- day pick the same primary model — keeping the model signature line
-- deterministic.
selectFictionModelChain :: Day -> NonEmpty Gemini.Model -> NonEmpty Gemini.Model
selectFictionModelChain day pool =
  let modelsList = NE.toList pool
      count = length modelsList
      offset = fromInteger (toModifiedJulianDay day `mod` toInteger count)
      rotated = drop offset modelsList <> take offset modelsList
  in case rotated of
    (m : ms) -> m :| ms
    []       -> pool

fictionEligibilityCutoff :: Day -> LocalTime
fictionEligibilityCutoff day = LocalTime day (TimeOfDay 22 0 0)

embedHeaders :: [Text]
embedHeaders = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader]

stripForPrompt :: Text -> Text
stripForPrompt content =
  let contentLines = T.lines content
      hasFrontmatter = case contentLines of
        (first:_) -> T.strip first == "---"
        []        -> False
      fmEnd = if hasFrontmatter
              then findClosingDash (drop 1 contentLines) 1
              else Nothing
      bodyLines = case fmEnd of
        Just index -> drop (index + 1) contentLines
        Nothing  -> contentLines
      body = T.unlines bodyLines
      firstEmbedIdx = findFirstIndex embedHeaders body
      fictionIdx = indexOfHeader fictionSectionHeader body
      updatesIdx = indexOfHeader updatesSectionHeader body
      cutoff = minimum $ filter (>= 0) [firstEmbedIdx, fictionIdx, updatesIdx, T.length body]
  in T.strip $ T.take cutoff body

findClosingDash :: [Text] -> Int -> Maybe Int
findClosingDash [] _ = Nothing
findClosingDash (l:rest) index =
  if T.strip l == "---" then Just index else findClosingDash rest (index + 1)

findFirstIndex :: [Text] -> Text -> Int
findFirstIndex headers body =
  let indices = fmap (`indexOfHeader` body) headers
      valid = filter (>= 0) indices
  in case valid of
    [] -> T.length body
    _  -> minimum valid

indexOfHeader :: Text -> Text -> Int
indexOfHeader header body =
  case T.breakOn header body of
    (before, rest) | not (T.null rest) -> T.length before
    _ -> -1

reflectionNeedsFiction :: Text -> Bool
reflectionNeedsFiction content = not (T.isInfixOf fictionSectionHeader content)

buildFictionPrompt :: Text -> (Text, Text)
buildFictionPrompt strippedContent =
  let system = "You are an inventive fiction writer crafting one tiny story per day.\n\
               \\n\
               \Your task:\n\
               \1. Read today's daily reflection note below\n\
               \2. Find the SINGLE most distinctive thread in today's topics — the one image, tension, question, or detail that makes TODAY different from every other day\n\
               \3. Write a short, vivid piece of fiction (UNDER 100 words) that grows out of that specific thread\n\
               \\n\
               \VOICE AND VIBE:\n\
               \- Write an engaging FIRST-PERSON narrative, or a tightly-scoped THIRD-PERSON narrative that stays close to a single character\n\
               \- Ground it in a concrete scene: a real place, a specific moment, a character actually doing something\n\
               \- Let the theme fall out of the specifics of today's topics so that each day feels unmistakably its own\n\
               \- Favor sensory detail, a small narrative arc, and a distinct narrator over abstract, generic musing\n\
               \- AVOID stale, interchangeable imagery (shifting sands, humming networks, woven tapestries, whispering winds, grand looms, glittering surfaces). Surprise the reader instead.\n\
               \\n\
               \FORMATTING RULES:\n\
               \- Every sentence MUST begin with an emoji that fits that sentence\n\
               \- NEVER use quotation marks (no \", no ', no `, no curly quotes)\n\
               \- Keep it UNDER 100 words\n\
               \- Do NOT name or directly quote the specific books, videos, articles, or people — transform them into the story\n\
               \- Do NOT include any heading or title — output ONLY the fiction text\n\
               \- Output ONLY the fiction — no explanation, no theme list, no preamble"
      user = "Write today's short fiction, inspired by the most distinctive thread in this daily reflection:\n\n" <> strippedContent
  in (system, user)

parseFictionResponse :: Text -> Text
parseFictionResponse raw =
  let t1 = stripCodeFences raw
      t2 = T.replace fictionSectionHeader "" t1
      t3 = removeQuotationMarks t2
  in T.strip t3

removeQuotationMarks :: Text -> Text
removeQuotationMarks = T.filter (\c ->
  c /= '"' && c /= '\'' && c /= '`'
  && c /= '\x2018' && c /= '\x2019'
  && c /= '\x201c' && c /= '\x201d')

buildFictionSignature :: Text -> Text
buildFictionSignature model = "\n\n✍️ Written by " <> model

applyFiction :: Text -> Text -> Maybe Text -> Text
applyFiction content fiction mModel =
  let signature = maybe "" buildFictionSignature mModel
      sectionBlock = fictionSectionHeader <> "\n\n" <> fiction <> signature
      embedIndices = filter (>= 0) $ fmap (`indexOfHeader` content) embedHeaders
      updatesIdx = indexOfHeader updatesSectionHeader content
      candidates = filter (>= 0) (updatesIdx : embedIndices)
      insertBeforeIdx = case candidates of
        [] -> -1
        _  -> minimum candidates
  in if insertBeforeIdx >= 0
    then
      let before = T.stripEnd (T.take insertBeforeIdx content)
          after = T.drop insertBeforeIdx content
      in before <> "\n\n" <> sectionBlock <> "\n\n" <> after
    else
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"

data FictionConfig = FictionConfig
  { models      :: NonEmpty Gemini.Model
  , noteContent :: Text
  } deriving (Show, Eq)

data FictionResult = FictionResult
  { fiction        :: Text
  , model          :: Text
  , updatedContent :: Text
  } deriving (Show, Eq)

generateFiction :: FictionConfig -> (NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)) -> IO FictionResult
generateFiction config callModel = do
  let stripped = stripForPrompt (noteContent config)
      prompt = buildFictionPrompt stripped
  (text, usedModel) <- callModel (models config) prompt
  let fictionText = parseFictionResponse text
      newContent = applyFiction (noteContent config) fictionText (Just usedModel)
  pure FictionResult
    { fiction = fictionText
    , model = usedModel
    , updatedContent = newContent
    }
