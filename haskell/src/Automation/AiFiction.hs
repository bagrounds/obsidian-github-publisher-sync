module Automation.AiFiction
  ( fictionSectionHeader
  , defaultFictionModel
  , stripForPrompt
  , reflectionNeedsFiction
  , buildFictionPrompt
  , parseFictionResponse
  , buildFictionSignature
  , applyFiction
  , generateFiction
  , FictionConfig (..)
  , FictionResult (..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Automation.Types
  ( blueskySectionHeader
  , mastodonSectionHeader
  , tweetSectionHeader
  )

fictionSectionHeader :: Text
fictionSectionHeader = "## 🤖🐲 AI Fiction"

defaultFictionModel :: Text
defaultFictionModel = "gemini-2.5-flash"

updatesSectionHeader :: Text
updatesSectionHeader = "## 🔄 Updates"

embedHeaders :: [Text]
embedHeaders = [tweetSectionHeader, blueskySectionHeader, mastodonSectionHeader]

stripForPrompt :: Text -> Text
stripForPrompt content =
  let ls = T.lines content
      hasFrontmatter = case ls of
        (first:_) -> T.strip first == "---"
        []        -> False
      fmEnd = if hasFrontmatter
              then findClosingDash (drop 1 ls) 1
              else Nothing
      bodyLines = case fmEnd of
        Just idx -> drop (idx + 1) ls
        Nothing  -> ls
      body = T.unlines bodyLines
      firstEmbedIdx = findFirstIndex embedHeaders body
      fictionIdx = indexOfHeader fictionSectionHeader body
      updatesIdx = indexOfHeader updatesSectionHeader body
      cutoff = minimum $ filter (>= 0) [firstEmbedIdx, fictionIdx, updatesIdx, T.length body]
  in T.strip $ T.take cutoff body

findClosingDash :: [Text] -> Int -> Maybe Int
findClosingDash [] _ = Nothing
findClosingDash (l:rest) idx =
  if T.strip l == "---" then Just idx else findClosingDash rest (idx + 1)

findFirstIndex :: [Text] -> Text -> Int
findFirstIndex headers body =
  let indices = fmap (\h -> indexOfHeader h body) headers
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

stripCodeFences :: Text -> Text
stripCodeFences t =
  let t1 = case T.stripPrefix "```markdown\n" t of
              Just rest -> rest
              Nothing -> case T.stripPrefix "```md\n" t of
                Just rest -> rest
                Nothing -> case T.stripPrefix "```\n" t of
                  Just rest -> rest
                  Nothing -> t
      t2 = case T.stripSuffix "\n```" t1 of
              Just rest -> rest
              Nothing -> t1
  in t2

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
      embedIndices = filter (>= 0) $ fmap (\h -> indexOfHeader h content) embedHeaders
      updatesIdx = indexOfHeader updatesSectionHeader content
      candidates = filter (>= 0) (updatesIdx : embedIndices)
      insertBeforeIdx = case candidates of
        [] -> -1
        _  -> minimum candidates
  in case insertBeforeIdx >= 0 of
    True ->
      let before = T.stripEnd (T.take insertBeforeIdx content)
          after = T.drop insertBeforeIdx content
      in before <> "\n\n" <> sectionBlock <> "\n\n" <> after
    False ->
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"

data FictionConfig = FictionConfig
  { fcApiKey      :: Text
  , fcModels      :: [Text]
  , fcNoteContent :: Text
  } deriving (Show, Eq)

data FictionResult = FictionResult
  { frFiction        :: Text
  , frModel          :: Text
  , frUpdatedContent :: Text
  } deriving (Show, Eq)

generateFiction :: FictionConfig -> (Text -> [Text] -> (Text, Text) -> IO (Text, Text)) -> IO FictionResult
generateFiction config callModel = do
  let stripped = stripForPrompt (fcNoteContent config)
      prompt = buildFictionPrompt stripped
  (text, model) <- callModel (fcApiKey config) (fcModels config) prompt
  let fiction = parseFictionResponse text
      updatedContent = applyFiction (fcNoteContent config) fiction (Just model)
  pure FictionResult
    { frFiction = fiction
    , frModel = model
    , frUpdatedContent = updatedContent
    }
