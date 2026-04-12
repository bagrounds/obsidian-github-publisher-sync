module Automation.ReflectionTitle
  ( defaultTitleModel
  , extractLinkedTitles
  , extractTrailingEmojis
  , extractHeadingEmojis
  , stripTitlePrefixes
  , reflectionNeedsTitle
  , buildReflectionTitlePrompt
  , parseReflectionTitle
  , applyReflectionTitle
  , generateReflectionTitle
  , isReflectionFile
  , extractCreativeTitle
  , ReflectionTitleConfig (ReflectionTitleConfig, rtcModels, rtcNoteContent, rtcDate, rtcRecentTitles)
  , ReflectionTitleResult (ReflectionTitleResult, rtrTitle, rtrFullTitle, rtrModel, rtrUpdatedContent)
  ) where

import Data.Char (isDigit)
import Data.List (find, nub)
import Data.List.NonEmpty (NonEmpty)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeExtension)

import Automation.Types (updatesSectionHeader)
import Automation.Frontmatter (parseFrontmatter)
import Automation.Text (isEmoji, isEmojiOrSpace)
import qualified Automation.Gemini as Gemini

defaultTitleModel :: Gemini.Model
defaultTitleModel = Gemini.Gemini25Flash

extractHeadingEmojis :: Text -> Text
extractHeadingEmojis heading =
  let withoutHashes = T.stripStart $ T.dropWhile (== '#') heading
      linkContent = case T.breakOn "[" withoutHashes of
        (_, rest) | not (T.null rest) ->
          let inner = T.takeWhile (/= ']') (T.drop 1 rest)
          in inner
        _ -> withoutHashes
      pipeContent = case T.breakOn "|" linkContent of
        (_, rest) | not (T.null rest) -> T.strip (T.drop 1 rest)
        _ -> T.strip linkContent
      emojiChars = T.takeWhile isEmojiOrSpace pipeContent
  in T.strip emojiChars

isUpdatesSectionHeading :: Text -> Bool
isUpdatesSectionHeading l = T.stripEnd l == updatesSectionHeader

extractTrailingEmojis :: Text -> Text
extractTrailingEmojis noteContent =
  let ls = T.lines noteContent
      h2Lines = filter (\l -> T.isPrefixOf "## " l && not (isUpdatesSectionHeading l)) ls
      extracted = fmap extractHeadingEmojis h2Lines
      deduped = nub $ filter (not . T.null) extracted
  in T.concat deduped

stripTitlePrefixes :: Text -> Text
stripTitlePrefixes title =
  let withoutDate = case T.unpack (T.take 11 title) of
        (y1:y2:y3:y4:'-':m1:m2:'-':d1:d2:' ':_)
          | all isDigit [y1,y2,y3,y4,m1,m2,d1,d2] ->
            case T.breakOn "| " (T.drop 10 title) of
              (_, rest) | not (T.null rest) -> T.drop 2 rest
              _ -> T.drop 11 title
        _ -> title
      withoutEmojis = T.dropWhile isEmojiOrSpace withoutDate
  in T.strip withoutEmojis

extractLinkedTitles :: Text -> [Text]
extractLinkedTitles noteContent =
  let (_, body) = parseFrontmatter noteContent
      ls = T.lines body
      lsBeforeUpdates = takeWhile (not . isUpdatesSectionHeading) ls
      listItems = filter (T.isPrefixOf "- " . T.stripStart) lsBeforeUpdates
      titles = concatMap extractTitlesFromLine listItems
  in filter (not . T.null) $ fmap stripTitlePrefixes titles

extractTitlesFromLine :: Text -> [Text]
extractTitlesFromLine line =
  extractWikiLinkTitles line <> extractMarkdownLinkTitles line

extractWikiLinkTitles :: Text -> [Text]
extractWikiLinkTitles t = case T.breakOn "[[" t of
  (_, rest) | not (T.null rest) ->
    let afterOpen = T.drop 2 rest
        (content, remainder) = T.breakOn "]]" afterOpen
        display = case T.breakOn "|" content of
          (_, afterPipe) | not (T.null afterPipe) -> T.strip (T.drop 1 afterPipe)
          _ -> T.strip content
    in display : extractWikiLinkTitles (T.drop 2 remainder)
  _ -> []

extractMarkdownLinkTitles :: Text -> [Text]
extractMarkdownLinkTitles t = case T.breakOn "](" t of
  (before, rest) | not (T.null rest) ->
    let (_, afterRemainder) = T.breakOn ")" (T.drop 2 rest)
        titlePart = case T.breakOnEnd "[" before of
          (_, display) | not (T.null display) -> [T.strip display]
          _ -> []
    in titlePart <> extractMarkdownLinkTitles (T.drop 1 afterRemainder)
  _ -> []

reflectionNeedsTitle :: Text -> Text -> Bool
reflectionNeedsTitle content date =
  let titleLine = findTitleLine (T.lines content)
  in case titleLine of
    Nothing -> True
    Just tl ->
      let val = T.strip $ T.drop 6 tl
          unquoted = T.dropAround (\c -> c == '"' || c == '\'') val
      in unquoted == date

findTitleLine :: [Text] -> Maybe Text
findTitleLine = foldr (\l acc -> if T.isPrefixOf "title:" l then Just l else acc) Nothing

buildReflectionTitlePrompt :: [Text] -> [Text] -> (Text, Text)
buildReflectionTitlePrompt linkedTitles recentTitles =
  let examplesBlock = T.intercalate "\n" $ fmap ("- " <>) recentTitles
      system = "You create short, creative titles from a list of content titles.\n\
               \\n\
               \YOUR GOAL: produce a grammatically coherent sentence or phrase — NOT a list of keywords.\n\
               \\n\
               \PROCESS (follow these steps internally):\n\
               \\n\
               \STEP 1 — FULL WORD INVENTORY: For EVERY word in EVERY content title, label it with its part(s) of speech.\n\
               \\n\
               \STEP 2 — SENTENCE TEMPLATES: Looking ONLY at the parts-of-speech inventory, draft 2–3 grammatical sentence or phrase templates.\n\
               \\n\
               \STEP 3 — FILL TEMPLATES: For each template, try several combinations of words that fit the POS slots — choosing exactly one word per content title.\n\
               \\n\
               \STEP 4 — COMPARE & ITERATE: Compare all filled-in candidates. Keep iterating until you have a coherent phrase.\n\
               \\n\
               \STEP 5 — EMOJI ENRICHMENT: Prefix each chosen word with 1 relevant emoji, with a space between emoji and word.\n\
               \\n\
               \RULES:\n\
               \- Use exactly one word from EACH content title — every title must contribute ONE word\n\
               \- The result MUST read as a coherent sentence or phrase when emojis are removed\n\
               \- Always put a space between emoji(s) and word\n\
               \- Do NOT include any trailing category emojis — those are added separately\n\
               \- Do NOT include any date prefix\n\
               \- Your response must contain ONLY the final title — no preamble, no explanation, no commentary\n\
               \- Do NOT start with phrases like \"Here's\", \"Here is\", \"Title:\", \"Sure\", or any other text before the title\n\
               \- The very first character of your response MUST be an emoji\n\
               \\n\
               \GOOD TITLE EXAMPLES (for style reference):\n" <> examplesBlock
      titlesBlock = T.intercalate "\n" $
        zipWith (\i t -> T.pack (show i) <> ". " <> t) [(1::Int)..] linkedTitles
      user = "Build a coherent emoji-enriched sentence using one word from each of these content titles:\n\n" <> titlesBlock
  in (system, user)

parseReflectionTitle :: Text -> Text
parseReflectionTitle raw =
  let cleaned = raw
        & stripCodeFences
        & T.dropAround (\c -> c == '"' || c == '\'')
        & T.replace "`" ""
        & stripDatePrefix
      selected = selectTitleLine cleaned
  in normalizeEmojiSpacing selected

selectTitleLine :: Text -> Text
selectTitleLine t =
  let nonEmptyLines = filter (not . T.null . T.strip) (T.lines t)
      emojiLine = find (startsWithEmoji . T.stripStart) nonEmptyLines
  in case emojiLine of
    Just l -> T.strip l
    Nothing -> case nonEmptyLines of
      (first:_) -> stripInlinePreamble (T.strip first)
      [] -> ""

startsWithEmoji :: Text -> Bool
startsWithEmoji t = case T.uncons t of
  Just (c, _) -> isEmoji c
  Nothing -> False

stripInlinePreamble :: Text -> Text
stripInlinePreamble t =
  case T.findIndex isEmoji t of
    Just idx | idx > 0 -> T.strip (T.drop idx t)
    _ -> t

(&) :: a -> (a -> b) -> b
(&) x f = f x

stripCodeFences :: Text -> Text
stripCodeFences t =
  let t1 = case T.stripPrefix "```markdown\n" t of
              Just rest -> rest
              Nothing -> case T.stripPrefix "```md\n" t of
                Just rest -> rest
                Nothing -> fromMaybe t (T.stripPrefix "```\n" t)
      t2 = fromMaybe t1 (T.stripSuffix "\n```" t1)
  in t2

stripDatePrefix :: Text -> Text
stripDatePrefix t = case T.unpack (T.take 13 t) of
  (y1:y2:y3:y4:'-':m1:m2:'-':d1:d2:' ':'|':' ':_)
    | all isDigit [y1,y2,y3,y4,m1,m2,d1,d2] -> T.drop 13 t
  _ -> t

normalizeEmojiSpacing :: Text -> Text
normalizeEmojiSpacing = id

applyReflectionTitle :: Text -> Text -> Text -> Text
applyReflectionTitle content date creativeTitle =
  let fullTitle = date <> " | " <> creativeTitle
      withFm = updateTitleFrontmatter content fullTitle
  in updateH1Heading withFm date fullTitle

updateTitleFrontmatter :: Text -> Text -> Text
updateTitleFrontmatter content fullTitle =
  let ls = T.lines content
  in case ls of
    (first : rest)
      | T.strip first == "---" ->
        case break (\l -> T.strip l == "---") rest of
          (fmLines, closingDash : body) ->
            let updatedFm = updateFmFields fmLines fullTitle
            in T.unlines (["---"] <> updatedFm <> [closingDash] <> body)
          _ -> content
    _ -> content

updateFmFields :: [Text] -> Text -> [Text]
updateFmFields fmLines fullTitle =
  let quoted = "\"" <> T.replace "\\" "\\\\" (T.replace "\"" "\\\"" fullTitle) <> "\""
      hasTitle = any (T.isPrefixOf "title:") fmLines
      hasAliases = any (T.isPrefixOf "aliases:") fmLines
      updateLine l
        | T.isPrefixOf "title:" l = "title: " <> quoted
        | otherwise = l
      withTitle = if hasTitle
        then fmap updateLine fmLines
        else fmLines <> ["title: " <> quoted]
      updateAliases [] = []
      updateAliases (l:rest)
        | T.isPrefixOf "aliases:" l =
          l : ("  - " <> quoted) : dropWhile (\r -> T.isPrefixOf "  -" r || T.isPrefixOf "  - " r) rest
        | otherwise = l : updateAliases rest
  in if hasAliases
    then updateAliases withTitle
    else withTitle <> ["aliases:", "  - " <> quoted]

updateH1Heading :: Text -> Text -> Text -> Text
updateH1Heading content date fullTitle =
  let ls = T.lines content
      updatedLines = fmap (\l ->
        if T.isPrefixOf "# " l && T.isInfixOf date l
        then "# " <> fullTitle
        else l) ls
  in T.unlines updatedLines

data ReflectionTitleConfig = ReflectionTitleConfig
  { rtcModels       :: NonEmpty Gemini.Model
  , rtcNoteContent  :: Text
  , rtcDate         :: Text
  , rtcRecentTitles :: [Text]
  } deriving (Show, Eq)

data ReflectionTitleResult = ReflectionTitleResult
  { rtrTitle          :: Text
  , rtrFullTitle      :: Text
  , rtrModel          :: Text
  , rtrUpdatedContent :: Text
  } deriving (Show, Eq)

generateReflectionTitle :: ReflectionTitleConfig -> (NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)) -> IO ReflectionTitleResult
generateReflectionTitle config callModel = do
  let linkedTitles = extractLinkedTitles (rtcNoteContent config)
      trailingEmojis = extractTrailingEmojis (rtcNoteContent config)
      prompt = buildReflectionTitlePrompt linkedTitles (rtcRecentTitles config)
  (text, model) <- callModel (rtcModels config) prompt
  let creativePart = parseReflectionTitle text
      title = if T.null trailingEmojis then creativePart else creativePart <> " " <> trailingEmojis
      fullTitle = rtcDate config <> " | " <> title
      updatedContent = applyReflectionTitle (rtcNoteContent config) (rtcDate config) title
  pure ReflectionTitleResult
    { rtrTitle = title
    , rtrFullTitle = fullTitle
    , rtrModel = model
    , rtrUpdatedContent = updatedContent
    }

isReflectionFile :: FilePath -> Bool
isReflectionFile filename =
  length filename == 13
    && takeExtension filename == ".md"
    && all isDigit (take 4 filename)
    && filename !! 4 == '-'
    && all isDigit (take 2 (drop 5 filename))
    && filename !! 7 == '-'
    && all isDigit (take 2 (drop 8 filename))

extractCreativeTitle :: Text -> Text
extractCreativeTitle content =
  case find (T.isPrefixOf "title:") (T.lines content) of
    Just matched ->
      let value = T.strip (T.drop 6 matched)
          unquoted = T.dropAround (\c -> c == '"' || c == '\'') value
      in case T.breakOn " | " unquoted of
           (_, rest) | not (T.null rest) -> T.drop 3 rest
           _ -> ""
    Nothing -> ""
