module Automation.AiFiction
  ( fictionSectionHeader
  , defaultFictionModel
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

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, LocalTime (..), TimeOfDay (..))

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
  let system = "You are a creative fiction writer. Your task is to:\n\
               \\n\
               \1. Read the content from today's daily reflection note\n\
               \2. Identify 2-4 abstract themes from the content\n\
               \3. Write a short piece of engaging fiction (UNDER 100 words) inspired by those themes\n\
               \\n\
               \RULES:\n\
               \- Every sentence MUST begin with an emoji\n\
               \- NEVER use quotation marks (no \", no ', no `, no curly quotes)\n\
               \- Keep it under 100 words\n\
               \- The fiction should be evocative and slightly philosophical\n\
               \- Abstract the themes — do NOT directly reference the specific books, videos, or articles\n\
               \- Do NOT include any heading or title — just the fiction text\n\
               \- Output ONLY the fiction — no explanation, no theme list, no preamble"
      user = "Write a short fiction piece inspired by themes from this daily reflection:\n\n" <> strippedContent
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
