module Automation.InternalLinking
  ( ContentEntry (..)
  , LinkCandidate (..)
  , FileResult (..)
  , LinkingResult (..)
  , defaultLinkingModel
  , linkableDirs
  , indexableDirs
  , traversableDirs
  , stripEmojis
  , escapeRegex
  , formatWikilink
  , extractContext
  , buildContentIndex
  , extractLinkedPaths
  , findMostRecentReflection
  , bfsTraversal
  , maskProtectedRegions
  , contentAlreadyLinksTo
  , findLinkCandidates
  , buildIdentificationPrompt
  , identifyBooksWithGemini
  , applyReplacements
  , alreadyAnalyzed
  , extractBody
  , processFile
  , run
  ) where

import Automation.BlogPrompt (todayPacific)
import Automation.Frontmatter (parseFrontmatter)
import Automation.Gemini
  ( GenerationConfig (..)
  , GeminiRequest (..)
  , GeminiResponse (..)
  , generateContent
  )
import Automation.Json (decode)
import Control.Concurrent (threadDelay)
import Data.Char (ord)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (Manager)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, takeDirectory, (</>))
import Text.Regex.TDFA ((=~))
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE

-- --------------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------------

defaultLinkingModel :: Text
defaultLinkingModel = "gemini-3.1-flash-lite-preview"

minTitleLength :: Int
minTitleLength = 8

maxGeminiRetries :: Int
maxGeminiRetries = 3

initialBackoffUs :: Int
initialBackoffUs = 5_000_000

maxBackoffUs :: Int
maxBackoffUs = 60_000_000

linkableDirs :: [Text]
linkableDirs = ["books"]

indexableDirs :: [Text]
indexableDirs =
  [ "books", "articles", "topics", "software", "people"
  , "products", "games", "videos", "presentations", "tools"
  ]

traversableDirs :: [Text]
traversableDirs =
  indexableDirs
    <> ["reflections", "chickie-loo", "auto-blog-zero", "systems-for-public-good"]

-- --------------------------------------------------------------------------
-- Types
-- --------------------------------------------------------------------------

data ContentEntry = ContentEntry
  { ceRelativePath :: Text
  , ceTitle        :: Text
  , cePlainTitle   :: Text
  } deriving (Show, Eq)

data LinkCandidate = LinkCandidate
  { lcEntry       :: ContentEntry
  , lcMatchedText :: Text
  , lcPosition    :: Int
  , lcContext     :: Text
  } deriving (Show, Eq)

data FileResult = FileResult
  { frRelativePath :: Text
  , frModified     :: Bool
  , frLinksAdded   :: Int
  } deriving (Show, Eq)

data LinkingResult = LinkingResult
  { lrFilesVisited    :: Int
  , lrFilesModified   :: Int
  , lrTotalLinksAdded :: Int
  , lrFilesSkipped    :: Int
  , lrFileResults     :: [FileResult]
  } deriving (Show, Eq)

-- --------------------------------------------------------------------------
-- Pure utility functions
-- --------------------------------------------------------------------------

stripEmojis :: Text -> Text
stripEmojis =
  T.intercalate " "
    . filter (not . T.null)
    . T.split (== ' ')
    . T.map (\c -> if isEmoji c then ' ' else c)
  where
    isEmoji :: Char -> Bool
    isEmoji c =
      let cp = ord c
      in  cp >= 0x1F600 && cp <= 0x1F64F
       || cp >= 0x1F300 && cp <= 0x1F5FF
       || cp >= 0x1F680 && cp <= 0x1F6FF
       || cp >= 0x1F1E0 && cp <= 0x1F1FF
       || cp >= 0x2600  && cp <= 0x27BF
       || cp >= 0x2300  && cp <= 0x23FF
       || cp >= 0x2702  && cp <= 0x27B0
       || cp >= 0xFE00  && cp <= 0xFE0F
       || cp >= 0x1F900 && cp <= 0x1F9FF
       || cp >= 0x1FA00 && cp <= 0x1FA6F
       || cp >= 0x1FA70 && cp <= 0x1FAFF
       || cp == 0x200D
       || cp == 0x20E3
       || cp >= 0xE0020 && cp <= 0xE007F
       || cp == 0xFE0E

escapeRegex :: Text -> Text
escapeRegex = T.concatMap escChar
  where
    specials :: Set.Set Char
    specials = Set.fromList ".*+?^${}()|[]\\"
    escChar c
      | Set.member c specials = "\\" <> T.singleton c
      | otherwise             = T.singleton c

formatWikilink :: ContentEntry -> Text
formatWikilink entry =
  let target = maybe (ceRelativePath entry) id
                 (T.stripSuffix ".md" (ceRelativePath entry))
  in "[[" <> target <> "|" <> ceTitle entry <> "]]"

extractContext :: Text -> Int -> Int -> Text
extractContext content pos matchLen =
  let radius = 100
      start  = max 0 (pos - radius)
      end    = min (T.length content) (pos + matchLen + radius)
      prefix = if start > 0 then "..." else ""
      suffix = if end < T.length content then "..." else ""
      slice  = T.take (end - start) (T.drop start content)
  in prefix <> slice <> suffix

extractBody :: Text -> Text
extractBody content =
  let ls = T.splitOn "\n" content
  in case ls of
    (first : rest)
      | T.strip first == "---" ->
          case break (\l -> T.strip l == "---") rest of
            (_, [])          -> content
            (_, _ : bodyLs)  -> T.intercalate "\n" bodyLs
    _ -> content

alreadyAnalyzed :: Text -> Bool
alreadyAnalyzed content =
  let (fm, _) = parseFrontmatter content
  in case Map.lookup "force_analyze_links" fm of
    Just "true" -> False
    _           -> Map.member "link_analysis_model" fm

-- --------------------------------------------------------------------------
-- Masking protected regions
-- --------------------------------------------------------------------------

maskProtectedRegions :: Text -> Text
maskProtectedRegions =
  maskBold
    . maskUrls
    . maskHeadings
    . maskWikilinks
    . maskMarkdownLinks
    . maskInlineCode
    . maskFencedCode
    . maskFrontmatter

maskFrontmatter :: Text -> Text
maskFrontmatter content =
  case T.stripPrefix "---\n" content of
    Nothing -> content
    Just afterOpen ->
      case T.breakOn "\n---\n" afterOpen of
        (_, "") -> content
        (fm, rest) ->
          let fmBlock = "---\n" <> fm <> "\n---\n"
              afterBlock = T.drop (T.length "\n---\n") rest
          in T.replicate (T.length fmBlock) " " <> afterBlock

maskFencedCode :: Text -> Text
maskFencedCode = maskBetweenFences

maskBetweenFences :: Text -> Text
maskBetweenFences input = go input
  where
    go txt =
      let (before, rest) = breakOnFence txt
      in case rest of
        Nothing -> txt
        Just (fence, afterOpen) ->
          case T.breakOn ("\n" <> fence) afterOpen of
            (_, "") -> before <> T.replicate (T.length fence) " "
                          <> T.replicate (T.length afterOpen) " "
            (block, closing) ->
              let closingFence = T.take (T.length fence + 1) closing
                  afterClose   = T.drop (T.length fence + 1) closing
              in before
                   <> T.replicate (T.length fence) " "
                   <> T.replicate (T.length block) " "
                   <> T.replicate (T.length closingFence) " "
                   <> go afterClose

    breakOnFence :: Text -> (Text, Maybe (Text, Text))
    breakOnFence txt =
      case T.breakOn "```" txt of
        (pre, rest)
          | T.null rest ->
              case T.breakOn "~~~" txt of
                (pre2, rest2)
                  | T.null rest2 -> (txt, Nothing)
                  | otherwise    ->
                      let (fence, afterFence) = T.span (== '~') rest2
                          afterLine = T.takeWhile (/= '\n') afterFence
                          restAfterLine = T.drop (T.length afterLine) afterFence
                      in (pre2, Just (fence <> afterLine, restAfterLine))
          | otherwise ->
              let (fence, afterFence) = T.span (== '`') rest
                  afterLine = T.takeWhile (/= '\n') afterFence
                  restAfterLine = T.drop (T.length afterLine) afterFence
              in case T.breakOn "~~~" txt of
                (pre2, rest2)
                  | T.null rest2 -> (pre, Just (fence <> afterLine, restAfterLine))
                  | T.length pre2 < T.length pre ->
                      let (fence2, afterFence2) = T.span (== '~') rest2
                          afterLine2 = T.takeWhile (/= '\n') afterFence2
                          restAfterLine2 = T.drop (T.length afterLine2) afterFence2
                      in (pre2, Just (fence2 <> afterLine2, restAfterLine2))
                  | otherwise -> (pre, Just (fence <> afterLine, restAfterLine))

maskInlineCode :: Text -> Text
maskInlineCode = replaceAllRegex "`[^`\n]+`"

maskMarkdownLinks :: Text -> Text
maskMarkdownLinks = maskMdLinks

maskMdLinks :: Text -> Text
maskMdLinks input = go input
  where
    go txt =
      case T.breakOn "[" txt of
        (_, "") -> txt
        (before, rest) ->
          case T.breakOn "](" (T.drop 1 rest) of
            (_, "") -> before <> "[" <> go (T.drop 1 rest)
            (linkText, afterBracket) ->
              case T.breakOn ")" (T.drop 2 afterBracket) of
                (_, "") -> before <> "[" <> go (T.drop 1 rest)
                (url, afterParen) ->
                  let fullMatch = "[" <> linkText <> "](" <> url <> ")"
                  in before
                       <> T.replicate (T.length fullMatch) " "
                       <> go (T.drop 1 afterParen)

maskWikilinks :: Text -> Text
maskWikilinks = maskWikiL

maskWikiL :: Text -> Text
maskWikiL input = go input
  where
    go txt =
      case T.breakOn "[[" txt of
        (_, "") -> txt
        (before, rest) ->
          case T.breakOn "]]" (T.drop 2 rest) of
            (_, "") -> txt
            (inner, afterClose) ->
              let fullMatch = "[[" <> inner <> "]]"
              in before
                   <> T.replicate (T.length fullMatch) " "
                   <> go (T.drop 2 afterClose)

maskHeadings :: Text -> Text
maskHeadings input =
  T.intercalate "\n" (fmap maskHeadingLine (T.splitOn "\n" input))
  where
    maskHeadingLine :: Text -> Text
    maskHeadingLine line
      | isHeading line = T.replicate (T.length line) " "
      | otherwise      = line

    isHeading :: Text -> Bool
    isHeading line =
      let (hashes, rest) = T.span (== '#') line
          hashCount = T.length hashes
      in hashCount >= 1 && hashCount <= 6 && T.isPrefixOf " " rest

maskUrls :: Text -> Text
maskUrls = replaceAllRegex "https?://[^] \t\n)]+"

maskBold :: Text -> Text
maskBold input = go input
  where
    go txt =
      case T.breakOn "**" txt of
        (_, "") -> txt
        (before, rest) ->
          before <> "  " <> go (T.drop 2 rest)

replaceAllRegex :: String -> Text -> Text
replaceAllRegex pat input = go input
  where
    go txt
      | T.null txt = txt
      | otherwise  =
          let s = T.unpack txt
          in case (s =~ pat :: (String, String, String)) of
            (_, "", _)      -> txt
            (before, match, after) ->
              T.pack before
                <> T.replicate (length match) " "
                <> go (T.pack after)

-- --------------------------------------------------------------------------
-- Content already links check
-- --------------------------------------------------------------------------

contentAlreadyLinksTo :: Text -> ContentEntry -> Bool
contentAlreadyLinksTo content entry =
  let pathNoMd = maybe (ceRelativePath entry) id
                   (T.stripSuffix ".md" (ceRelativePath entry))
  in T.isInfixOf (pathNoMd <> "]") content
  || T.isInfixOf (pathNoMd <> "|") content
  || T.isInfixOf (pathNoMd <> "#") content
  || T.isInfixOf (pathNoMd <> ".") content

-- --------------------------------------------------------------------------
-- Build content index
-- --------------------------------------------------------------------------

buildContentIndex :: FilePath -> IO [ContentEntry]
buildContentIndex contentDir =
  fmap concat $ traverse (scanDir contentDir) linkableDirs

scanDir :: FilePath -> Text -> IO [ContentEntry]
scanDir contentDir dirName = do
  let dirPath = contentDir </> T.unpack dirName
  exists <- doesDirectoryExist dirPath
  case exists of
    False -> pure []
    True  -> do
      files <- listDirectory dirPath
      let mdFiles = filter (\f -> hasSuffix ".md" f && f /= "index.md") files
      fmap (mapMaybe id) $ traverse (readEntry contentDir dirName) mdFiles

readEntry :: FilePath -> Text -> FilePath -> IO (Maybe ContentEntry)
readEntry contentDir dirName file = do
  let relativePath = dirName <> "/" <> T.pack file
      filePath     = contentDir </> T.unpack relativePath
  content <- TIO.readFile filePath
  let (fm, _) = parseFrontmatter content
  pure $ do
    title <- Map.lookup "title" fm
    let plain = stripEmojis title
    if T.length plain < minTitleLength
      then Nothing
      else Just ContentEntry
        { ceRelativePath = relativePath
        , ceTitle        = title
        , cePlainTitle   = plain
        }

hasSuffix :: String -> String -> Bool
hasSuffix suf str = drop (length str - length suf) str == suf

-- --------------------------------------------------------------------------
-- Link extraction (for BFS)
-- --------------------------------------------------------------------------

extractLinkedPaths :: Text -> Text -> FilePath -> [Text]
extractLinkedPaths body noteRelativePath contentDir =
  let noteDir = takeDirectory (contentDir </> T.unpack noteRelativePath)
      seen    = Set.empty :: Set.Set Text
  in snd $ foldl' collectLink (seen, [])
       (markdownLinks body noteDir contentDir <> wikiLinks body noteDir contentDir)

collectLink :: (Set.Set Text, [Text]) -> Text -> (Set.Set Text, [Text])
collectLink (seen, acc) rel
  | T.isPrefixOf ".." rel = (seen, acc)
  | Set.member rel seen   = (seen, acc)
  | otherwise             = (Set.insert rel seen, acc <> [rel])

markdownLinks :: Text -> FilePath -> FilePath -> [Text]
markdownLinks body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\]\\(([^)]+\\.md)\\)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target])
        | not ("http://" `isPrefixOfS` target) && not ("https://" `isPrefixOfS` target) ->
            let absTarget  = normalizeFilePath (noteDir </> target)
                relPath    = makeRelativeTo contentDir absTarget
            in T.pack relPath : go after
        | otherwise -> go after
      _ -> []

wikiLinks :: Text -> FilePath -> FilePath -> [Text]
wikiLinks body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\[\\[([^\\]|#]+)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target]) ->
        let trimmed = strip target
            withMd  = if hasSuffix ".md" trimmed then trimmed else trimmed <> ".md"
            rel
              | '/' `elem` withMd = T.pack withMd
              | otherwise         =
                  let absTarget = normalizeFilePath (noteDir </> withMd)
                  in T.pack (makeRelativeTo contentDir absTarget)
        in rel : go after
      _ -> []

isPrefixOfS :: String -> String -> Bool
isPrefixOfS [] _          = True
isPrefixOfS _ []          = False
isPrefixOfS (x:xs) (y:ys) = x == y && isPrefixOfS xs ys

strip :: String -> String
strip = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

normalizeFilePath :: FilePath -> FilePath
normalizeFilePath = joinSlash . resolve . splitSlash
  where
    resolve :: [String] -> [String]
    resolve = foldl' step []

    step :: [String] -> String -> [String]
    step acc "."      = acc
    step (_:rest) ".." = rest
    step acc seg       = seg : acc

makeRelativeTo :: FilePath -> FilePath -> FilePath
makeRelativeTo base target =
  let baseParts   = splitSlash base
      targetParts = splitSlash target
      common      = length $ takeWhile id $ zipWith (==) baseParts targetParts
      remaining   = drop common targetParts
  in joinSlash remaining

splitSlash :: FilePath -> [String]
splitSlash = fmap T.unpack . filter (not . T.null) . T.splitOn "/" . T.pack

joinSlash :: [String] -> FilePath
joinSlash []     = ""
joinSlash [x]    = x
joinSlash (x:xs) = x </> joinSlash xs

-- --------------------------------------------------------------------------
-- BFS traversal
-- --------------------------------------------------------------------------

findMostRecentReflection :: FilePath -> IO (Maybe Text)
findMostRecentReflection contentDir = do
  let reflDir = contentDir </> "reflections"
  exists <- doesDirectoryExist reflDir
  case exists of
    False -> pure Nothing
    True  -> do
      files <- listDirectory reflDir
      let datePattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.md$" :: String
          dateFiles   = filter (\f -> (f :: String) =~ datePattern) files
          sorted      = sortBy (flip compare) dateFiles
      pure $ case sorted of
        (f : _) -> Just ("reflections/" <> T.pack f)
        []      -> Nothing

bfsTraversal :: FilePath -> IO [Text]
bfsTraversal contentDir = do
  mStart <- findMostRecentReflection contentDir
  case mStart of
    Nothing    -> pure []
    Just start -> do
      visitedRef <- newIORef (Set.singleton start)
      queueRef   <- newIORef [start]
      resultRef  <- newIORef ([] :: [Text])
      bfsLoop contentDir visitedRef queueRef resultRef
      reverse <$> readIORef resultRef

bfsLoop :: FilePath -> IORef (Set.Set Text) -> IORef [Text] -> IORef [Text] -> IO ()
bfsLoop contentDir visitedRef queueRef resultRef = do
  queue <- readIORef queueRef
  case queue of
    [] -> pure ()
    (current : rest) -> do
      modifyIORef' queueRef (const rest)
      let filePath = contentDir </> T.unpack current
      exists <- doesFileExist filePath
      let isIndex = takeBaseName (T.unpack current) == "index"
      case exists && not isIndex of
        False -> bfsLoop contentDir visitedRef queueRef resultRef
        True  -> do
          modifyIORef' resultRef (current :)
          content <- TIO.readFile filePath
          let (_, body) = parseFrontmatter content
              linked    = extractLinkedPaths body current contentDir
          visited <- readIORef visitedRef
          let newLinks = filter (\l -> not (Set.member l visited)) linked
          modifyIORef' visitedRef (\s -> foldl' (flip Set.insert) s newLinks)
          modifyIORef' queueRef (<> newLinks)
          bfsLoop contentDir visitedRef queueRef resultRef

-- --------------------------------------------------------------------------
-- Link candidate discovery
-- --------------------------------------------------------------------------

findLinkCandidates :: [ContentEntry] -> Text -> Text -> Text -> [LinkCandidate]
findLinkCandidates index content masked selfPath =
  let sortedIndex = sortBy (\a b -> compare (Down (T.length (cePlainTitle a)))
                                            (Down (T.length (cePlainTitle b)))) index
      (_, candidates) = foldl' findForEntry ([], []) sortedIndex
  in sortBy (\a b -> compare (lcPosition a) (lcPosition b)) candidates
  where
    findForEntry :: ([(Int, Int)], [LinkCandidate]) -> ContentEntry -> ([(Int, Int)], [LinkCandidate])
    findForEntry (ranges, cands) entry
      | ceRelativePath entry == selfPath = (ranges, cands)
      | contentAlreadyLinksTo content entry = (ranges, cands)
      | any (\c -> ceRelativePath (lcEntry c) == ceRelativePath entry) cands = (ranges, cands)
      | otherwise =
          let pat     = "\\b" <> T.unpack (escapeRegex (cePlainTitle entry)) <> "\\b"
              matches = findAllMatches pat (T.unpack masked)
          in case filter (\(p, len) -> not (overlaps ranges p (p + len))) matches of
            []             -> (ranges, cands)
            ((pos, len):_) ->
              let matchedText = T.take len (T.drop pos content)
                  ctx         = extractContext content pos len
                  candidate   = LinkCandidate
                    { lcEntry       = entry
                    , lcMatchedText = matchedText
                    , lcPosition    = pos
                    , lcContext     = ctx
                    }
              in ((pos, pos + len) : ranges, cands <> [candidate])

    overlaps :: [(Int, Int)] -> Int -> Int -> Bool
    overlaps ranges start end =
      any (\(rStart, rEnd) -> start < rEnd && end > rStart) ranges

findAllMatches :: String -> String -> [(Int, Int)]
findAllMatches pat str = go 0 str
  where
    go :: Int -> String -> [(Int, Int)]
    go _offset [] = []
    go offset s =
      case (s =~ pat :: (String, String, String)) of
        (_, "", _)      -> []
        (before, match, after) ->
          let pos = offset + length before
              len = length match
          in (pos, len) : go (pos + len) after

-- --------------------------------------------------------------------------
-- Gemini integration
-- --------------------------------------------------------------------------

buildIdentificationPrompt :: Text -> [ContentEntry] -> Text
buildIdentificationPrompt fileBody bookEntries =
  let bookList = T.intercalate "\n"
        $ fmap (\e -> "- \"" <> cePlainTitle e <> "\" (" <> ceRelativePath e <> ")") bookEntries
      systemPrompt = T.intercalate "\n"
        [ "You are a precise editorial assistant for a knowledge base of book reports. Your job is to identify genuine book references in a document."
        , ""
        , "You will receive:"
        , "1. The body text of a document."
        , "2. A list of book titles and their file paths."
        , ""
        , "Your task: Determine which books from the list are genuinely referenced in the document AS BOOKS (literary works). This means the text is discussing, recommending, citing, or listing the book itself — not merely using a word that happens to match a book title."
        , ""
        , "Rules:"
        , "- Return the relativePath of each book that is genuinely referenced as a book."
        , "- A book reference may use the main title without the subtitle."
        , "- DO NOT include a book if the matching word or phrase is used in a generic context."
        , "- DO include a book when the text explicitly discusses, recommends, or cites it as a literary work."
        , "- Be conservative: when in doubt, do NOT include the book."
        , ""
        , "Return ONLY a valid JSON array of relativePath strings for books genuinely referenced. Example: [\"books/thinking-fast-and-slow.md\", \"books/deep-learning.md\"]"
        , "If no books are genuinely referenced, return an empty array: []"
        , "No other text, no explanation, no markdown formatting."
        ]
  in systemPrompt <> "\n\nAvailable books:\n" <> bookList <> "\n\nDocument body:\n" <> fileBody

identifyBooksWithGemini :: Manager -> Text -> Text -> Text -> [ContentEntry] -> IO (Either Text [Text])
identifyBooksWithGemini _ _ _ _ [] = pure (Right [])
identifyBooksWithGemini manager apiKey model fileBody bookEntries = do
  let prompt = buildIdentificationPrompt fileBody bookEntries
  retryLoop manager apiKey model prompt 0 initialBackoffUs

retryLoop :: Manager -> Text -> Text -> Text -> Int -> Int -> IO (Either Text [Text])
retryLoop manager apiKey model prompt attempt backoff = do
  result <- generateContent manager GeminiRequest
    { grPrompt           = prompt
    , grModel            = model
    , grApiKey           = apiKey
    , grGenerationConfig = GenerationConfig
        { gcTemperature     = 0.0
        , gcMaxOutputTokens = 1024
        }
    }
  case result of
    Right resp ->
      pure (parseGeminiBookPaths (grText resp))
    Left err
      | isRateLimitErr err && attempt < maxGeminiRetries -> do
          putStrLn $ "  ⏳ Rate limit, retry " <> show (attempt + 1) <> "/" <> show maxGeminiRetries
            <> " in " <> show (backoff `div` 1_000_000) <> "s"
          threadDelay backoff
          retryLoop manager apiKey model prompt (attempt + 1) (min (backoff * 2) maxBackoffUs)
      | isDailyQuotaErr err ->
          pure (Left ("QuotaExhausted: " <> err))
      | otherwise ->
          pure (Left err)

isRateLimitErr :: Text -> Bool
isRateLimitErr msg =
  T.isInfixOf "429" msg
    || T.isInfixOf "RESOURCE_EXHAUSTED" msg
    || T.isInfixOf "quota" msg

isDailyQuotaErr :: Text -> Bool
isDailyQuotaErr msg =
  T.isInfixOf "quota" msg
    && (T.isInfixOf "daily" msg || T.isInfixOf "per day" msg || T.isInfixOf "PerDay" msg)

parseGeminiBookPaths :: Text -> Either Text [Text]
parseGeminiBookPaths raw =
  let cleaned = extractJsonArrayText raw
  in case decode (encodeToLbs cleaned) :: Maybe [Text] of
    Just paths -> Right paths
    Nothing    -> Left ("Failed to parse Gemini response as JSON array: " <> raw)
  where
    encodeToLbs :: Text -> LBS.ByteString
    encodeToLbs t = LBS.fromStrict (TE.encodeUtf8 t)

extractJsonArrayText :: Text -> Text
extractJsonArrayText txt =
  let stripped = T.strip txt
      noFences = stripCodeFences stripped
  in case (T.findIndex (== '[') noFences, findLastIndex (== ']') noFences) of
    (Just start, Just end) -> T.take (end - start + 1) (T.drop start noFences)
    _                      -> noFences

stripCodeFences :: Text -> Text
stripCodeFences txt =
  let noStart = maybe txt id (T.stripPrefix "```json" txt >>= Just . T.strip)
      noStart' = maybe noStart id (T.stripPrefix "```" noStart >>= Just . T.strip)
  in maybe noStart' id (T.stripSuffix "```" noStart' >>= Just . T.strip)

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt = go Nothing 0 (T.unpack txt)
  where
    go acc _ [] = acc
    go acc i (c : cs)
      | predicate c = go (Just i) (i + 1) cs
      | otherwise   = go acc (i + 1) cs

-- --------------------------------------------------------------------------
-- Replacement application
-- --------------------------------------------------------------------------

applyReplacements :: Text -> [LinkCandidate] -> [Bool] -> Text
applyReplacements content candidates validations =
  let validPairs = filter snd (zip candidates validations)
      sorted     = sortBy (\(a, _) (b, _) -> compare (Down (lcPosition a)) (Down (lcPosition b)))
                     validPairs
  in foldl' applyOne content (fmap fst sorted)
  where
    applyOne :: Text -> LinkCandidate -> Text
    applyOne acc candidate =
      let pos    = lcPosition candidate
          len    = T.length (lcMatchedText candidate)
          before = T.take pos acc
          after  = T.drop (pos + len) acc
          wl     = formatWikilink (lcEntry candidate)
      in before <> wl <> after

-- --------------------------------------------------------------------------
-- Frontmatter updates
-- --------------------------------------------------------------------------

updateFrontmatterFields :: FilePath -> [(Text, Text)] -> IO ()
updateFrontmatterFields filePath fields = do
  exists <- doesFileExist filePath
  case exists of
    False -> pure ()
    True  -> do
      raw <- TIO.readFile filePath
      let ls = T.splitOn "\n" raw
      case ls of
        (first : rest)
          | T.strip first == "---" ->
              case break (\l -> T.strip l == "---") rest of
                (_, []) -> pure ()
                (fmLines, closingDash : bodyLines) ->
                  let updatedFm = foldl' upsertField fmLines fields
                  in TIO.writeFile filePath
                       (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
        _ -> do
          let entries = T.intercalate "\n" $ fmap (\(k, v) -> k <> ": " <> v) fields
          TIO.writeFile filePath ("---\n" <> entries <> "\n---\n" <> raw)

upsertField :: [Text] -> (Text, Text) -> [Text]
upsertField ls (key, val) =
  let newLine   = key <> ": " <> val
      pat       = T.unpack key <> ":"
      replaced  = fmap (\l -> if matchesKey pat l then newLine else l) ls
      didReplace = any (matchesKey pat) ls
  in if didReplace then replaced else replaced <> [newLine]
  where
    matchesKey :: String -> Text -> Bool
    matchesKey p line = T.isPrefixOf (T.pack p) (T.stripStart line)

recordLinkAnalysis :: FilePath -> Text -> Text -> IO ()
recordLinkAnalysis filePath model timestamp =
  updateFrontmatterFields filePath
    [ ("link_analysis_model", model)
    , ("link_analysis_time", timestamp)
    , ("force_analyze_links", "false")
    ]

-- --------------------------------------------------------------------------
-- File processing
-- --------------------------------------------------------------------------

processFile :: Manager -> Text -> Text -> FilePath -> [ContentEntry] -> IO FileResult
processFile manager apiKey model filePath index = do
  let contentDir   = takeDirectory (takeDirectory filePath)
      relativePath = makeRelPathFromContentDir contentDir filePath
  content <- TIO.readFile filePath
  case alreadyAnalyzed content of
    True -> pure FileResult
      { frRelativePath = T.pack relativePath
      , frModified     = False
      , frLinksAdded   = 0
      }
    False -> do
      let body = extractBody content
          eligibleBooks = filter
            (\e -> ceRelativePath e /= T.pack relativePath
                && not (contentAlreadyLinksTo content e))
            index
      case eligibleBooks of
        [] -> do
          timestamp <- nowIso
          recordLinkAnalysis filePath model timestamp
          pure FileResult
            { frRelativePath = T.pack relativePath
            , frModified     = False
            , frLinksAdded   = 0
            }
        _ -> do
          geminiResult <- identifyBooksWithGemini manager apiKey model body eligibleBooks
          timestamp <- nowIso
          recordLinkAnalysis filePath model timestamp
          case geminiResult of
            Left _err -> pure FileResult
              { frRelativePath = T.pack relativePath
              , frModified     = False
              , frLinksAdded   = 0
              }
            Right identifiedPaths
              | null identifiedPaths -> pure FileResult
                  { frRelativePath = T.pack relativePath
                  , frModified     = False
                  , frLinksAdded   = 0
                  }
              | otherwise -> do
                  let identifiedSet = Set.fromList identifiedPaths
                  contentAfterFm <- TIO.readFile filePath
                  let masked          = maskProtectedRegions contentAfterFm
                      identifiedIndex = filter (\e -> Set.member (ceRelativePath e) identifiedSet) index
                      candidates      = findLinkCandidates identifiedIndex contentAfterFm masked (T.pack relativePath)
                  case candidates of
                    [] -> pure FileResult
                      { frRelativePath = T.pack relativePath
                      , frModified     = False
                      , frLinksAdded   = 0
                      }
                    _  -> do
                      let validations = replicate (length candidates) True
                          newContent  = applyReplacements contentAfterFm candidates validations
                      TIO.writeFile filePath newContent
                      putStrLn $ "  ✏️  " <> relativePath <> ": "
                        <> show (length candidates) <> " link(s) applied"
                      pure FileResult
                        { frRelativePath = T.pack relativePath
                        , frModified     = True
                        , frLinksAdded   = length candidates
                        }

makeRelPathFromContentDir :: FilePath -> FilePath -> FilePath
makeRelPathFromContentDir contentDir filePath =
  joinSlash $ drop (length (splitSlash contentDir)) (splitSlash filePath)

nowIso :: IO Text
nowIso = do
  today <- todayPacific
  pure (today <> "T00:00:00Z")

-- --------------------------------------------------------------------------
-- Orchestration
-- --------------------------------------------------------------------------

run :: Manager -> Text -> FilePath -> IO LinkingResult
run manager model contentDir = do
  putStrLn $ "🔗 Internal linking: model=" <> T.unpack model

  index <- buildContentIndex contentDir
  putStrLn $ "  📚 Index: " <> show (length index) <> " books"

  filesToVisit <- bfsTraversal contentDir
  putStrLn $ "  🔍 BFS: " <> show (length filesToVisit) <> " files reachable"

  apiKey <- lookupApiKey
  fileResults <- processFiles manager apiKey model contentDir index filesToVisit

  let filesModified  = length $ filter frModified fileResults
      totalLinks     = sum $ fmap frLinksAdded fileResults
      filesSkipped   = length $ filter (\r -> not (frModified r) && frLinksAdded r == 0) fileResults

  let result = LinkingResult
        { lrFilesVisited    = length filesToVisit
        , lrFilesModified   = filesModified
        , lrTotalLinksAdded = totalLinks
        , lrFilesSkipped    = filesSkipped
        , lrFileResults     = fileResults
        }

  putStrLn $ "  🏁 Complete: " <> show (lrFilesVisited result) <> " visited, "
    <> show filesModified <> " modified, " <> show totalLinks <> " links added, "
    <> show filesSkipped <> " skipped"

  pure result

processFiles :: Manager -> Text -> Text -> FilePath -> [ContentEntry] -> [Text] -> IO [FileResult]
processFiles manager apiKey model contentDir index filesToVisit = do
  inferenceRef <- newIORef (0 :: Int)
  resultRef    <- newIORef ([] :: [FileResult])
  go inferenceRef resultRef filesToVisit
  reverse <$> readIORef resultRef
  where
    maxInferencePerRun :: Int
    maxInferencePerRun = 1

    go :: IORef Int -> IORef [FileResult] -> [Text] -> IO ()
    go _ _ [] = pure ()
    go infRef resRef (relPath : rest) = do
      let filePath = contentDir </> T.unpack relPath
      fileResult <- processFile manager apiKey model filePath index
      modifyIORef' resRef (fileResult :)
      infCount <- readIORef infRef
      let calledGemini = not (isSkipped fileResult)
      case calledGemini of
        True -> do
          modifyIORef' infRef (+ 1)
          let newCount = infCount + 1
          case newCount >= maxInferencePerRun of
            True -> do
              putStrLn $ "  ⏹️  Inference limit reached: " <> show newCount <> "/" <> show maxInferencePerRun
              pure ()
            False -> go infRef resRef rest
        False -> go infRef resRef rest

    isSkipped :: FileResult -> Bool
    isSkipped fr = not (frModified fr) && frLinksAdded fr == 0

lookupApiKey :: IO Text
lookupApiKey = do
  mKey <- lookupEnv "GEMINI_API_KEY"
  pure $ maybe "" T.pack mKey


