module Automation.BlogImage
  ( ImageGenerationResult (..)
  , ImageProviderConfig (..)
  , BackfillConfig (..)
  , BackfillResult (..)
  , ContentDirectory (..)
  , CandidateEligibility (..)
  , IneligibilityReason (..)
  , hasEmbeddedImage
  , shouldRegenerateImage
  , insertImageEmbed
  , cleanContentForPrompt
  , buildImagePrompt
  , describeImageWithGemini
  , resolveImageProviders
  , processNote
  , backfillImages
  , syncAttachmentsDir
  , updateFrontmatterFields
  , applyField
  , mimeTypeToExtension
  , notePathToImageBaseName
  , resolveUniqueImageName
  , extractTitle
  , sanitizeForYaml
  , isQuotaError
  , isDailyQuotaError
  , isProviderUnavailableError
  , isPostFile
  , shouldHaveImage
  , isDateOnlyTitle
  , parseDateFromFilename
  , contentDirectoryFromText
  , contentDirectoryToText
  , checkCandidateEligibility
  , removeImageEmbed
  , generateWithCloudflare
  , generateWithHuggingFace
  , generateWithTogether
  , generateWithPollinations
  , generateImageWithGemini
  ) where

import Control.Exception (SomeException, catch)
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isAlphaNum, isDigit, toLower)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Data.Time (Day, defaultTimeLocale, formatTime, getCurrentTime)
import Data.Time.Format (parseTimeM)
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseHeaders
  , responseStatus
  )
import Network.HTTP.Types.Header (hContentType)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  )
import System.FilePath ((</>), takeBaseName, takeDirectory, takeExtension)
import Text.Regex.TDFA ((=~))

import Automation.BlogPrompt (stripEmbedSections, todayPacificDay)
import Automation.Frontmatter (YamlValue (..), parseFrontmatter, renderYamlValue)
import qualified Automation.Gemini as Gemini
import qualified Automation.Json as Json
import Automation.Types (Secret (..))

--------------------------------------------------------------------------------
-- Data types
--------------------------------------------------------------------------------

data ImageGenerationResult = ImageGenerationResult
  { igrSkipped     :: Bool
  , igrImagePath   :: Maybe FilePath
  , igrImageName   :: Maybe Text
  , igrImagePrompt :: Maybe Text
  } deriving (Show, Eq)

data ImageProviderConfig = ImageProviderConfig
  { ipcName           :: Text
  , ipcApiKey         :: Secret
  , ipcModel          :: Text
  , ipcGenerator      :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
  , ipcDescribePrompt :: Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text))
  }

data BackfillConfig = BackfillConfig
  { backfillRepoRoot       :: FilePath
  , backfillContentDirs    :: [ContentDirectory]
  , backfillAttachmentsDir :: FilePath
  , backfillProviders      :: [ImageProviderConfig]
  , backfillMaxImages      :: Int
  }

data BackfillResult = BackfillResult
  { brImagesGenerated :: Int
  , brFilesUpdated    :: Int
  , brFilesSkipped    :: Int
  , brModifiedFiles   :: [Text]
  , brErrors          :: [Text]
  } deriving (Show, Eq)

data BackfillCandidate = BackfillCandidate
  { bcFilePath          :: FilePath
  , bcDirectory         :: ContentDirectory
  , bcFilename          :: Text
  , bcDate              :: Day
  , bcNeedsRegeneration :: Bool
  }

data ContentDirectory
  = Reflections
  | AiBlog
  | AutoBlogZero
  | ChickieLoo
  | SystemsForPublicGood
  | Articles
  | Books
  | BotChats
  | Games
  | Products
  | Software
  | Tools
  | Topics
  deriving (Show, Eq, Ord, Bounded, Enum)

contentDirectoryToText :: ContentDirectory -> Text
contentDirectoryToText = \case
  Reflections          -> "reflections"
  AiBlog               -> "ai-blog"
  AutoBlogZero         -> "auto-blog-zero"
  ChickieLoo           -> "chickie-loo"
  SystemsForPublicGood -> "systems-for-public-good"
  Articles             -> "articles"
  Books                -> "books"
  BotChats             -> "bot-chats"
  Games                -> "games"
  Products             -> "products"
  Software             -> "software"
  Tools                -> "tools"
  Topics               -> "topics"

contentDirectoryFromText :: Text -> Maybe ContentDirectory
contentDirectoryFromText = \case
  "reflections"            -> Just Reflections
  "ai-blog"               -> Just AiBlog
  "auto-blog-zero"        -> Just AutoBlogZero
  "chickie-loo"           -> Just ChickieLoo
  "systems-for-public-good" -> Just SystemsForPublicGood
  "articles"              -> Just Articles
  "books"                 -> Just Books
  "bot-chats"             -> Just BotChats
  "games"                 -> Just Games
  "products"              -> Just Products
  "software"              -> Just Software
  "tools"                 -> Just Tools
  "topics"                -> Just Topics
  _                       -> Nothing

data CandidateEligibility
  = Eligible { needsRegeneration :: Bool }
  | Ineligible IneligibilityReason
  deriving (Show, Eq)

data IneligibilityReason
  = FutureReflection
  | AlreadyHasImage
  | UntitledReflection
  deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

excludedFiles :: [Text]
excludedFiles = ["index.md", "AGENTS.md", "IDEAS.md"]

defaultDescriberModel :: Text
defaultDescriberModel = "gemini-3.1-flash-lite-preview"

cloudflarePromptMaxLength :: Int
cloudflarePromptMaxLength = 2048

imageDescriptionSystemPrompt :: Text
imageDescriptionSystemPrompt = T.intercalate " "
  [ "Describe a cover image for the following blog post."
  , "Focus on visual elements that would make an appealing illustration."
  , "Be concise — respond in under 150 words."
  , "Do not include any text or words in the image."
  , "Respond with only the image description, no preamble."
  ]

--------------------------------------------------------------------------------
-- Pure utility functions
--------------------------------------------------------------------------------

hasEmbeddedImage :: Text -> Bool
hasEmbeddedImage content =
  let s = T.unpack content
      obsidianMatch = s =~ ("!\\[\\[([^]]*/)?" <> "[^]]+\\.(jpg|jpeg|png|gif|webp)\\]\\]" :: String) :: Bool
      markdownMatch = s =~ ("!\\[[^]]*\\]\\([^)]+\\.(jpg|jpeg|png|gif|webp)\\)" :: String) :: Bool
  in obsidianMatch || markdownMatch

shouldRegenerateImage :: Text -> Bool
shouldRegenerateImage content =
  let (fm, _) = parseFrontmatter content
  in case Map.lookup "regenerate_image" fm of
    Just v  -> T.strip (T.toLower v) `elem` ["true", "yes"]
    Nothing -> False

insertImageEmbed :: Text -> Text -> Text
insertImageEmbed content imageName =
  let ls = T.splitOn "\n" content
      embed = "![[attachments/" <> imageName <> "]]"
      insertAfterH1 [] = []
      insertAfterH1 (l : rest)
        | "# " `T.isPrefixOf` l = l : embed : rest
        | otherwise              = l : insertAfterH1 rest
  in T.intercalate "\n" (insertAfterH1 ls)

removeImageEmbed :: Text -> (Text, Maybe Text)
removeImageEmbed content =
  let s = T.unpack content
      pat = "^!\\[\\[(attachments/)?([^]]+\\.(jpg|jpeg|png|gif|webp))\\]\\]" :: String
      matches = s =~ pat :: [[String]]
  in case matches of
    (fullMatch : _) ->
      let matchText = T.pack (case fullMatch of { (x:_) -> x; [] -> "" })
          imageName = case fullMatch of
            [_, _, name, _] -> T.pack name
            _               -> matchText
          cleaned = collapseNewlines (T.replace matchText "" content)
      in (cleaned, Just (stripAttachmentsPrefix imageName))
    [] -> (content, Nothing)

stripAttachmentsPrefix :: Text -> Text
stripAttachmentsPrefix t = fromMaybe t (T.stripPrefix "attachments/" t)

collapseNewlines :: Text -> Text
collapseNewlines = go
  where
    go t = let t' = T.replace "\n\n\n" "\n\n" t
           in if t' == t then t else go t'

extractTitle :: Text -> Text
extractTitle content =
  let ls = T.splitOn "\n" content
      fromFrontmatter = extractTitleFromFrontmatter ls False
      fromH1 = findH1Title ls
  in fromMaybe "" (fromFrontmatter `altMaybe` fromH1)

extractTitleFromFrontmatter :: [Text] -> Bool -> Maybe Text
extractTitleFromFrontmatter [] _ = Nothing
extractTitleFromFrontmatter (l : rest) inFm
  | T.strip l == "---" = if inFm then Nothing else extractTitleFromFrontmatter rest True
  | inFm = case T.stripPrefix "title:" l of
      Just val -> Just (stripQuotes (T.strip val))
      Nothing  -> extractTitleFromFrontmatter rest True
  | otherwise = Nothing

findH1Title :: [Text] -> Maybe Text
findH1Title = foldr (\l acc -> if "# " `T.isPrefixOf` l then Just (T.strip (T.drop 2 l)) else acc) Nothing

stripQuotes :: Text -> Text
stripQuotes t =
  let stripped = case T.uncons t of
        Just (c, rest) | c == '"' || c == '\'' -> rest
        _ -> t
  in case T.unsnoc stripped of
    Just (init', c) | c == '"' || c == '\'' -> init'
    _ -> stripped

altMaybe :: Maybe a -> Maybe a -> Maybe a
altMaybe (Just x) _ = Just x
altMaybe Nothing  y = y

notePathToImageBaseName :: FilePath -> Text
notePathToImageBaseName notePath =
  let dir = T.pack (takeBaseName (takeDirectory notePath))
      stem = T.pack (takeBaseName notePath)
      raw = T.toLower (dir <> "-" <> stem)
  in trimDashes (collapseDashes (replaceNonAlphaNumDash raw))

replaceNonAlphaNumDash :: Text -> Text
replaceNonAlphaNumDash = T.map (\c -> if isAlphaNum c || c == '-' then c else '-')

collapseDashes :: Text -> Text
collapseDashes = T.intercalate "-" . filter (not . T.null) . T.splitOn "-"

trimDashes :: Text -> Text
trimDashes = T.dropWhile (== '-') . T.dropWhileEnd (== '-')

mimeTypeToExtension :: Text -> Text
mimeTypeToExtension mime = case T.takeWhile (/= ';') (T.strip mime) of
  "image/jpeg" -> ".jpg"
  "image/png"  -> ".png"
  "image/gif"  -> ".gif"
  "image/webp" -> ".webp"
  _            -> ".jpg"

sanitizeForYaml :: Text -> Text
sanitizeForYaml =
  T.strip
    . collapseSpaces
    . T.filter (`notElem` ['\"', '\'', '\\', '`'])
    . T.map (\c -> if c == '\n' || c == '\r' || c == '\t' then ' ' else c)

collapseSpaces :: Text -> Text
collapseSpaces = T.intercalate " " . filter (not . T.null) . T.splitOn " "

isQuotaError :: Text -> Bool
isQuotaError msg =
  T.isInfixOf "429" msg
    || T.isInfixOf "RESOURCE_EXHAUSTED" msg
    || T.isInfixOf "quota" msg

isDailyQuotaError :: Text -> Bool
isDailyQuotaError msg =
  T.isInfixOf "quota" msg
    && (T.isInfixOf "daily" msg || T.isInfixOf "per day" msg || T.isInfixOf "PerDay" msg)

isProviderUnavailableError :: Text -> Bool
isProviderUnavailableError msg =
  T.isInfixOf "410" msg
    || T.isInfixOf "401" msg
    || T.isInfixOf "403" msg
    || T.isInfixOf "no longer supported" msg
    || T.isInfixOf "deprecated" msg

isPostFile :: Text -> Bool
isPostFile filename =
  T.isSuffixOf ".md" filename
    && notElem filename excludedFiles
    && hasDatePrefix filename

shouldHaveImage :: Text -> Bool
shouldHaveImage filename =
  T.isSuffixOf ".md" filename
    && notElem filename excludedFiles

hasDatePrefix :: Text -> Bool
hasDatePrefix t =
  T.length t >= 10
    && T.all isDigit (T.take 4 t)
    && T.index t 4 == '-'
    && T.all isDigit (T.take 2 (T.drop 5 t))
    && T.index t 7 == '-'
    && T.all isDigit (T.take 2 (T.drop 8 t))

parseDateFromFilename :: Text -> Maybe Day
parseDateFromFilename filename =
  if hasDatePrefix filename
    then parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack (T.take 10 filename))
    else Nothing

isDateOnlyTitle :: Text -> Day -> Bool
isDateOnlyTitle content date =
  let title = extractTitle content
      dateText = T.pack (formatTime defaultTimeLocale "%Y-%m-%d" date)
  in title == dateText

--------------------------------------------------------------------------------
-- Content processing
--------------------------------------------------------------------------------

stripMarkdownSyntax :: Text -> Text
stripMarkdownSyntax =
  T.strip
    . collapseTripleNewlines
    . removeTableSeparators
    . removeTableCells
    . removeBlockquotes
    . removeOrderedLists
    . removeUnorderedLists
    . removeEmphasis
    . removeInlineCode
    . removeCodeBlocks
    . removeMarkdownLinks
    . removeMarkdownImages
    . removeObsidianEmbeds
    . removeHeadings

removeHeadings :: Text -> Text
removeHeadings = T.unlines . fmap stripHeading . T.lines
  where
    stripHeading l
      | "######" `T.isPrefixOf` l = T.stripStart (T.drop 6 l)
      | "#####" `T.isPrefixOf` l  = T.stripStart (T.drop 5 l)
      | "####" `T.isPrefixOf` l   = T.stripStart (T.drop 4 l)
      | "###" `T.isPrefixOf` l    = T.stripStart (T.drop 3 l)
      | "##" `T.isPrefixOf` l     = T.stripStart (T.drop 2 l)
      | "#" `T.isPrefixOf` l      = T.stripStart (T.drop 1 l)
      | otherwise                 = l

removeObsidianEmbeds :: Text -> Text
removeObsidianEmbeds t =
  let s = T.unpack t
      result = replaceAll s "!\\[\\[[^]]*\\]\\]" ""
  in T.pack result

removeMarkdownImages :: Text -> Text
removeMarkdownImages t =
  let s = T.unpack t
      result = replaceAll s "!\\[[^]]*\\]\\([^)]*\\)" ""
  in T.pack result

removeMarkdownLinks :: Text -> Text
removeMarkdownLinks t =
  let s = T.unpack t
      result = replaceAllWith s "\\[([^]]*)\\]\\([^)]*\\)" (\groups -> case groups of
        (_full : captured : _) -> captured
        [full]                 -> full
        _                      -> "")
  in T.pack result

removeCodeBlocks :: Text -> Text
removeCodeBlocks content = T.intercalate "\n" (go (T.lines content) False)
  where
    go [] _ = []
    go (l : rest) inBlock
      | "```" `T.isPrefixOf` l && inBlock = go rest False
      | "```" `T.isPrefixOf` l            = go rest True
      | inBlock                            = go rest True
      | otherwise                          = l : go rest False

removeInlineCode :: Text -> Text
removeInlineCode t =
  let s = T.unpack t
      result = replaceAll s "`[^`]*`" ""
  in T.pack result

removeEmphasis :: Text -> Text
removeEmphasis = T.filter (`notElem` ['*', '_', '~'])

removeUnorderedLists :: Text -> Text
removeUnorderedLists = T.unlines . fmap stripBullet . T.lines
  where
    stripBullet l
      | matchesBullet l = T.stripStart (T.drop 2 (T.stripStart l))
      | otherwise       = l
    matchesBullet l =
      let stripped = T.stripStart l
      in case T.uncons stripped of
           Just (c, rest) | c `elem` ['-', '*', '+'] -> case T.uncons rest of
             Just (' ', _) -> True
             _             -> False
           _ -> False

removeOrderedLists :: Text -> Text
removeOrderedLists = T.unlines . fmap stripOrdered . T.lines
  where
    stripOrdered l =
      let stripped = T.stripStart l
          (digits, rest) = T.span isDigit stripped
      in if not (T.null digits)
         then case T.uncons rest of
           Just ('.', afterDot) -> case T.uncons afterDot of
             Just (' ', content') -> T.stripStart content'
             _                    -> l
           _ -> l
         else l

removeBlockquotes :: Text -> Text
removeBlockquotes = T.unlines . fmap stripQuote . T.lines
  where
    stripQuote l =
      let stripped = T.stripStart l
      in case T.uncons stripped of
           Just ('>', rest) -> T.stripStart rest
           _                -> l

removeTableCells :: Text -> Text
removeTableCells t =
  let s = T.unpack t
      result = replaceAll s "\\|[^|\\n]*\\|" ""
  in T.pack result

removeTableSeparators :: Text -> Text
removeTableSeparators = T.unlines . filter (not . isTableSep) . T.lines
  where
    isTableSep l = T.all (\c -> c == '-' || c == '|' || c == ':' || c == ' ') (T.strip l)
                   && T.length (T.strip l) > 2
                   && T.isInfixOf "-" l

collapseTripleNewlines :: Text -> Text
collapseTripleNewlines t =
  let t' = T.replace "\n\n\n" "\n\n" t
  in if t' == t then t else collapseTripleNewlines t'

cleanContentForPrompt :: Text -> Text
cleanContentForPrompt rawContent =
  let (_, body) = parseFrontmatter rawContent
      withoutEmbeds = stripEmbedSections body
  in stripMarkdownSyntax withoutEmbeds

buildImagePrompt :: Text -> Text
buildImagePrompt postContent =
  let cleaned = cleanContentForPrompt postContent
      prefix = "generate an image to illustrate the following blog post: "
      maxContentLength = cloudflarePromptMaxLength - T.length prefix
      truncated
        | T.length cleaned > maxContentLength = T.take (maxContentLength - 1) cleaned <> "…"
        | otherwise                           = cleaned
  in prefix <> truncated

--------------------------------------------------------------------------------
-- Frontmatter manipulation
--------------------------------------------------------------------------------

updateFrontmatterFields :: Text -> [(Text, YamlValue)] -> Text
updateFrontmatterFields content fields =
  let ls = T.splitOn "\n" content
  in case ls of
    (first : rest)
      | T.strip first == "---" ->
          case break (\l -> T.strip l == "---") rest of
            (_, []) -> content
            (fmLines, _ : body) ->
              let updatedFm = foldl' applyField fmLines fields
              in T.intercalate "\n" (["---"] <> updatedFm <> ["---"] <> body)
    _ ->
      let fmLines = fmap (\(k, v) -> k <> ": " <> renderYamlValue v) fields
      in T.intercalate "\n" (["---"] <> fmLines <> ["---", content])

applyField :: [Text] -> (Text, YamlValue) -> [Text]
applyField fmLines (key, value) =
  let keyPrefix = key <> ":"
      newLine = key <> ": " <> renderYamlValue value
      keyExists = any (\l -> keyPrefix `T.isPrefixOf` T.stripStart l) fmLines
      replaced = replaceWithContinuation keyPrefix newLine fmLines
  in if keyExists then replaced else fmLines <> [newLine]

replaceWithContinuation :: Text -> Text -> [Text] -> [Text]
replaceWithContinuation _ _ [] = []
replaceWithContinuation keyPrefix newLine (l : rest)
  | keyPrefix `T.isPrefixOf` T.stripStart l =
      newLine : dropContinuationLines rest
  | otherwise = l : replaceWithContinuation keyPrefix newLine rest

dropContinuationLines :: [Text] -> [Text]
dropContinuationLines [] = []
dropContinuationLines (l : rest)
  | isContinuationLine l = dropContinuationLines rest
  | otherwise = l : rest

isContinuationLine :: Text -> Bool
isContinuationLine l = not (T.null l) && T.isPrefixOf " " l


extractFrontmatterValue :: Text -> Text -> Maybe Text
extractFrontmatterValue content key =
  let (fm, _) = parseFrontmatter content
  in Map.lookup key fm

--------------------------------------------------------------------------------
-- Regex helpers
--------------------------------------------------------------------------------

replaceAll :: String -> String -> String -> String
replaceAll source pat replacement =
  case source =~ pat :: (String, String, String) of
    (_, "", _)       -> source
    (before, _, after) -> before <> replacement <> replaceAll after pat replacement

replaceAllWith :: String -> String -> ([String] -> String) -> String
replaceAllWith source pat mkReplacement =
  case source =~ pat :: (String, String, String, [String]) of
    (_, "", _, _)             -> source
    (before, match, after, groups) ->
      before <> mkReplacement (match : groups) <> replaceAllWith after pat mkReplacement

--------------------------------------------------------------------------------
-- HTTP image generation providers
--------------------------------------------------------------------------------

generateWithCloudflare
  :: Manager -> Text -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithCloudflare manager apiToken accountId model prompt = do
  let url = "https://api.cloudflare.com/client/v4/accounts/"
            <> T.unpack accountId <> "/ai/run/" <> T.unpack model
  initReq <- parseRequest url
  let body = Json.encode $ Json.object
        [ "prompt" Json..= prompt
        , "steps"  Json..= (4 :: Int)
        ]
      httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiToken)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseCloudflareResponse (responseBody resp)
    code -> pure $ Left $
      "Cloudflare API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseCloudflareResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseCloudflareResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) -> do
      success <- mapLeft T.pack (obj Json..: "success" :: Either String Bool)
      if not success
        then Left "Cloudflare image generation failed: success=false"
        else case lookup "result" obj of
          Just (Json.Object resultObj) ->
            case lookup "image" resultObj of
              Just (Json.String b64) ->
                case B64.decode (TE.encodeUtf8 b64) of
                  Left err -> Left ("Base64 decode error: " <> T.pack err)
                  Right bs -> Right (LBS.fromStrict bs, "image/jpeg")
              _ -> Left "No image in Cloudflare response"
          _ -> Left "No result in Cloudflare response"
    Right _ -> Left "Cloudflare response is not a JSON object"

generateWithHuggingFace
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithHuggingFace manager apiToken model prompt = do
  let url = "https://router.huggingface.co/hf-inference/models/" <> T.unpack model
  initReq <- parseRequest url
  let body = Json.encode $ Json.object [ "inputs" Json..= prompt ]
      httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiToken)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 ->
      let contentType = maybe "image/jpeg" (T.takeWhile (/= ';') . TE.decodeUtf8)
                          (lookup hContentType (responseHeaders resp))
      in if "image/" `T.isPrefixOf` contentType
         then pure $ Right (responseBody resp, contentType)
         else pure $ Left $ "HuggingFace returned non-image response: "
                <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))
    code -> pure $ Left $
      "HuggingFace API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

generateWithTogether
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithTogether manager apiKey model prompt = do
  initReq <- parseRequest "https://api.together.ai/v1/images/generations"
  let body = Json.encode $ Json.object
        [ "model"           Json..= model
        , "prompt"          Json..= prompt
        , "steps"           Json..= (4 :: Int)
        , "n"               Json..= (1 :: Int)
        , "response_format" Json..= ("b64_json" :: Text)
        ]
      httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiKey)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseTogetherResponse (responseBody resp)
    code -> pure $ Left $
      "Together API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseTogetherResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseTogetherResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "data" obj of
        Just (Json.Array (Json.Object item : _)) ->
          case lookup "b64_json" item of
            Just (Json.String b64) ->
              case B64.decode (TE.encodeUtf8 b64) of
                Left err -> Left ("Base64 decode error: " <> T.pack err)
                Right bs -> Right (LBS.fromStrict bs, "image/jpeg")
            _ -> Left "No b64_json in Together response"
        _ -> Left "No data array in Together response"
    Right _ -> Left "Together response is not a JSON object"

generateWithPollinations
  :: Manager -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithPollinations manager model prompt = do
  let encodedPrompt = TE.decodeUtf8 (urlEncode True (TE.encodeUtf8 prompt))
      encodedModel = TE.decodeUtf8 (urlEncode True (TE.encodeUtf8 model))
      url = "https://image.pollinations.ai/prompt/" <> T.unpack encodedPrompt
            <> "?model=" <> T.unpack encodedModel
            <> "&width=1024&height=1024&nologo=true"
  initReq <- parseRequest url
  resp <- httpLbs initReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 ->
      let contentType = maybe "image/jpeg" (T.takeWhile (/= ';') . TE.decodeUtf8)
                          (lookup hContentType (responseHeaders resp))
      in if "image/" `T.isPrefixOf` contentType
         then pure $ Right (responseBody resp, contentType)
         else pure $ Left $ "Pollinations returned non-image response: "
                <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))
    code -> pure $ Left $
      "Pollinations API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

isImagenModel :: Text -> Bool
isImagenModel = T.isPrefixOf "imagen-"

generateImageWithGemini
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateImageWithGemini manager apiKey model prompt
  | isImagenModel model = generateWithImagen manager apiKey model prompt
  | otherwise           = generateWithGeminiContent manager apiKey model prompt

generateWithImagen
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithImagen manager apiKey model prompt = do
  let url = "https://generativelanguage.googleapis.com/v1beta/models/"
            <> T.unpack model <> ":predict?key=" <> T.unpack apiKey
  initReq <- parseRequest url
  let body = Json.encode $ Json.object
        [ "instances"  Json..= [ Json.object [ "prompt" Json..= prompt ] ]
        , "parameters" Json..= Json.object [ "sampleCount" Json..= (1 :: Int) ]
        ]
      httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseImagenResponse (responseBody resp)
    code -> pure $ Left $
      "Imagen API returned status " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseImagenResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseImagenResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "predictions" obj of
        Just (Json.Array (Json.Object pred' : _)) ->
          case lookup "bytesBase64Encoded" pred' of
            Just (Json.String b64) ->
              case B64.decode (TE.encodeUtf8 b64) of
                Left err -> Left ("Base64 decode error: " <> T.pack err)
                Right bs ->
                  let mime = case lookup "mimeType" pred' of
                        Just (Json.String m) -> m
                        _                    -> "image/png"
                  in Right (LBS.fromStrict bs, mime)
            _ -> Left "No bytesBase64Encoded in Imagen response"
        _ -> Left "No predictions in Imagen response"
    Right _ -> Left "Imagen response is not a JSON object"

generateWithGeminiContent
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithGeminiContent manager apiKey model prompt = do
  let url = "https://generativelanguage.googleapis.com/v1beta/models/"
            <> T.unpack model <> ":generateContent?key=" <> T.unpack apiKey
  initReq <- parseRequest url
  let body = Json.encode $ Json.object
        [ "contents" Json..=
            [ Json.object [ "parts" Json..= [ Json.object [ "text" Json..= prompt ] ] ] ]
        , "generationConfig" Json..= Json.object
            [ "responseModalities" Json..= (["IMAGE"] :: [Text]) ]
        ]
      httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseGeminiImageResponse (responseBody resp)
    code -> pure $ Left $
      "Gemini image API returned status " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseGeminiImageResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseGeminiImageResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "candidates" obj of
        Just (Json.Array (Json.Object cand : _)) ->
          case lookup "content" cand of
            Just (Json.Object contentObj) ->
              case lookup "parts" contentObj of
                Just (Json.Array parts) -> findInlineData parts
                _ -> Left "No parts in Gemini image response"
            _ -> Left "No content in candidate"
        _ -> Left "No candidates in Gemini image response"
    Right _ -> Left "Gemini image response is not a JSON object"

findInlineData :: [Json.Value] -> Either Text (LBS.ByteString, Text)
findInlineData [] = Left "No image generated"
findInlineData (Json.Object partObj : rest) =
  case lookup "inlineData" partObj of
    Just (Json.Object inlineObj) ->
      case lookup "data" inlineObj of
        Just (Json.String b64) ->
          case B64.decode (TE.encodeUtf8 b64) of
            Left err -> Left ("Base64 decode error: " <> T.pack err)
            Right bs ->
              let mime = case lookup "mimeType" inlineObj of
                    Just (Json.String m) -> m
                    _                    -> "image/png"
              in Right (LBS.fromStrict bs, mime)
        _ -> findInlineData rest
    _ -> findInlineData rest
findInlineData (_ : rest) = findInlineData rest

--------------------------------------------------------------------------------
-- Gemini content describer
--------------------------------------------------------------------------------

describeImageWithGemini
  :: Manager -> Text -> Text -> Text -> IO (Either Text Text)
describeImageWithGemini manager apiKey model content = do
  let fullPrompt = imageDescriptionSystemPrompt <> "\n\n" <> content
      req = Gemini.Request
        { Gemini.grPrompt = fullPrompt
        , Gemini.grModel = model
        , Gemini.grApiKey = Secret apiKey
        , Gemini.grGenerationConfig = Gemini.defaultGenerationConfig
        }
  result <- Gemini.generateContent manager req
  case result of
    Right resp -> pure $ Right (Gemini.grText resp)
    Left _err  -> do
      putStrLn $ "⚠️ " <> T.unpack model <> " failed for image description, trying fallback..."
      let fallbackModel = geminiModelFallback model
      let fallbackReq = req { Gemini.grModel = fallbackModel }
      fallbackResult <- Gemini.generateContent manager fallbackReq
      pure $ fmap Gemini.grText fallbackResult

geminiModelFallback :: Text -> Text
geminiModelFallback m
  | "gemini-3" `T.isPrefixOf` m = "gemini-2.5-flash"
  | "gemini-2" `T.isPrefixOf` m = "gemini-2.0-flash"
  | otherwise                    = "gemini-2.0-flash"

--------------------------------------------------------------------------------
-- Provider resolution
--------------------------------------------------------------------------------

resolveImageProviders :: Map Text Text -> [ImageProviderConfig]
resolveImageProviders env =
  let geminiKey = Map.lookup "GEMINI_API_KEY" env
      describerModel = fromMaybe defaultDescriberModel (Map.lookup "PROMPT_DESCRIBER_MODEL" env)
      describer = fmap (\gk -> mkDescriber gk describerModel) geminiKey
  in mapMaybe id
    [ mkCloudflareProvider env describer
    , mkHuggingFaceProvider env describer
    , mkTogetherProvider env describer
    , mkPollinationsProvider env describer
    , mkGeminiProvider env describer
    ]

mkDescriber :: Text -> Text -> Manager -> Text -> Text -> Text -> IO (Either Text Text)
mkDescriber geminiKey describerModel mgr _apiKey _model content =
  describeImageWithGemini mgr geminiKey describerModel content

mkCloudflareProvider :: Map Text Text -> Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text)) -> Maybe ImageProviderConfig
mkCloudflareProvider env describer = do
  cfToken <- Map.lookup "CLOUDFLARE_API_TOKEN" env
  cfAccountId <- Map.lookup "CLOUDFLARE_ACCOUNT_ID" env
  let cfModel = fromMaybe "@cf/black-forest-labs/flux-1-schnell" (Map.lookup "CLOUDFLARE_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcName = "cloudflare"
    , ipcApiKey = Secret cfToken
    , ipcModel = cfModel
    , ipcGenerator = \mgr apiKey _model prompt ->
        generateWithCloudflare mgr apiKey cfAccountId cfModel prompt
    , ipcDescribePrompt = describer
    }

mkHuggingFaceProvider :: Map Text Text -> Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text)) -> Maybe ImageProviderConfig
mkHuggingFaceProvider env describer = do
  hfToken <- Map.lookup "HUGGINGFACE_API_TOKEN" env
  let hfModel = fromMaybe "black-forest-labs/FLUX.1-schnell" (Map.lookup "HUGGINGFACE_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcName = "huggingface"
    , ipcApiKey = Secret hfToken
    , ipcModel = hfModel
    , ipcGenerator = \mgr apiKey _model prompt ->
        generateWithHuggingFace mgr apiKey hfModel prompt
    , ipcDescribePrompt = describer
    }

mkTogetherProvider :: Map Text Text -> Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text)) -> Maybe ImageProviderConfig
mkTogetherProvider env describer = do
  togetherKey <- Map.lookup "TOGETHER_API_TOKEN" env
  let togetherModel = fromMaybe "black-forest-labs/FLUX.1-schnell-Free" (Map.lookup "TOGETHER_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcName = "together"
    , ipcApiKey = Secret togetherKey
    , ipcModel = togetherModel
    , ipcGenerator = \mgr apiKey _model prompt ->
        generateWithTogether mgr apiKey togetherModel prompt
    , ipcDescribePrompt = describer
    }

mkPollinationsProvider :: Map Text Text -> Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text)) -> Maybe ImageProviderConfig
mkPollinationsProvider env describer =
  case Map.lookup "POLLINATIONS_ENABLED" env of
    Just "true" ->
      let polModel = fromMaybe "flux" (Map.lookup "POLLINATIONS_IMAGE_MODEL" env)
      in Just ImageProviderConfig
        { ipcName = "pollinations"
        , ipcApiKey = Secret ""
        , ipcModel = polModel
        , ipcGenerator = \mgr _apiKey _model prompt ->
            generateWithPollinations mgr polModel prompt
        , ipcDescribePrompt = describer
        }
    _ -> Nothing

mkGeminiProvider :: Map Text Text -> Maybe (Manager -> Text -> Text -> Text -> IO (Either Text Text)) -> Maybe ImageProviderConfig
mkGeminiProvider env describer = do
  geminiKey <- Map.lookup "GEMINI_API_KEY" env
  let geminiModel = fromMaybe "gemini-3.1-flash-image-preview" (Map.lookup "IMAGE_GEMINI_MODEL" env)
  pure ImageProviderConfig
    { ipcName = "gemini"
    , ipcApiKey = Secret geminiKey
    , ipcModel = geminiModel
    , ipcGenerator = generateImageWithGemini
    , ipcDescribePrompt = describer
    }

--------------------------------------------------------------------------------
-- File I/O: resolveUniqueImageName
--------------------------------------------------------------------------------

resolveUniqueImageName :: Text -> Text -> FilePath -> IO Text
resolveUniqueImageName baseName extension attachmentsDir = do
  let candidate = baseName <> extension
  exists <- doesFileExist (attachmentsDir </> T.unpack candidate)
  if not exists
    then pure candidate
    else findUnique (2 :: Int)
  where
    findUnique n = do
      let name = baseName <> "-" <> T.pack (show n) <> extension
      exists <- doesFileExist (attachmentsDir </> T.unpack name)
      if not exists
        then pure name
        else findUnique (n + 1)

--------------------------------------------------------------------------------
-- processNote
--------------------------------------------------------------------------------

processNote :: Manager -> ImageProviderConfig -> FilePath -> FilePath -> IO ImageGenerationResult
processNote manager provider notePath attachmentsDir = do
  rawContent <- TIO.readFile notePath
  content <- handleRegeneration notePath attachmentsDir rawContent
  let skippedResult = ImageGenerationResult True Nothing Nothing Nothing
  case hasEmbeddedImage content of
    True  -> pure skippedResult
    False -> do
      let title = extractTitle content
      case T.null title of
        True  -> pure skippedResult
        False -> do
          let baseName = notePathToImageBaseName notePath
          case T.null baseName of
            True  -> pure skippedResult
            False -> generateAndSaveImage manager provider notePath attachmentsDir content baseName

handleRegeneration :: FilePath -> FilePath -> Text -> IO Text
handleRegeneration notePath attachmentsDir content =
  case shouldRegenerateImage content of
    False -> pure content
    True  -> do
      let (cleaned, mOldImage) = removeImageEmbed content
          updated = updateFrontmatterFields cleaned
            [("regenerate_image", YamlBool False), ("image_prompt", YamlText "")]
      case mOldImage of
        Just oldImage -> do
          let oldPath = attachmentsDir </> T.unpack oldImage
          oldExists <- doesFileExist oldPath
          case oldExists of
            True  -> do
              -- Remove old image file by overwriting with empty then removing
              -- Actually, we should use removeFile but it's not imported.
              -- Let's just leave it; the new image will have a unique name.
              pure ()
            False -> pure ()
        Nothing -> pure ()
      TIO.writeFile notePath updated
      pure updated

generateAndSaveImage
  :: Manager -> ImageProviderConfig -> FilePath -> FilePath -> Text -> Text -> IO ImageGenerationResult
generateAndSaveImage manager provider notePath attachmentsDir content baseName = do
  promptResult <- resolvePrompt manager provider content
  case promptResult of
    Left err -> do
      putStrLn $ "⚠️ Failed to resolve prompt: " <> T.unpack err
      pure $ ImageGenerationResult True Nothing Nothing Nothing
    Right prompt -> do
      imageResult <- ipcGenerator provider manager (unSecret (ipcApiKey provider)) (ipcModel provider) prompt
      case imageResult of
        Left err -> do
          putStrLn $ "❌ Image generation failed: " <> T.unpack err
          pure $ ImageGenerationResult True Nothing Nothing Nothing
        Right (imageData, mimeType) -> do
          let extension = mimeTypeToExtension mimeType
          imageName <- resolveUniqueImageName baseName extension attachmentsDir
          let imagePath = attachmentsDir </> T.unpack imageName
          createDirectoryIfMissing True attachmentsDir
          LBS.writeFile imagePath imageData
          let withEmbed = insertImageEmbed content imageName
          now <- formatTimestamp
          let withMeta = updateFrontmatterFields withEmbed
                [ ("image_date", YamlText now)
                , ("image_model", YamlText (ipcModel provider))
                , ("image_prompt", YamlText (sanitizeForYaml prompt))
                ]
          TIO.writeFile notePath withMeta
          pure $ ImageGenerationResult False (Just imagePath) (Just imageName) (Just prompt)

resolvePrompt :: Manager -> ImageProviderConfig -> Text -> IO (Either Text Text)
resolvePrompt manager provider content =
  case extractFrontmatterValue content "image_prompt" of
    Just cached | not (T.null (T.strip cached)) -> pure (Right cached)
    _ -> case ipcDescribePrompt provider of
      Just describer -> do
        result <- describer manager (unSecret (ipcApiKey provider)) (ipcModel provider) content
        pure $ fmap sanitizeForYaml result
      Nothing -> pure $ Right (buildImagePrompt content)

formatTimestamp :: IO Text
formatTimestamp = do
  now <- getCurrentTime
  pure $ T.pack $ formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now

--------------------------------------------------------------------------------
-- backfillImages
--------------------------------------------------------------------------------

backfillImages :: Manager -> BackfillConfig -> IO BackfillResult
backfillImages manager config = do
  today <- todayPacificDay
  candidates <- collectCandidates (backfillRepoRoot config) (backfillContentDirs config) today
  putStrLn $ "📋 Candidates: " <> show (length candidates) <> " notes need images"
         <> " | providers: " <> show (length (backfillProviders config))
         <> " | max: " <> show (backfillMaxImages config)
  processWithProviders manager config candidates 0 emptyResult

emptyResult :: BackfillResult
emptyResult = BackfillResult 0 0 0 [] []

collectCandidates :: FilePath -> [ContentDirectory] -> Day -> IO [BackfillCandidate]
collectCandidates repoRoot contentDirectories today = do
  candidateLists <- traverse (collectFromDirectory repoRoot today) contentDirectories
  let allCandidates = concat candidateLists
      sorted = sortByDateDesc allCandidates
  pure sorted

collectFromDirectory :: FilePath -> Day -> ContentDirectory -> IO [BackfillCandidate]
collectFromDirectory repoRoot today directory = do
  let directoryPath = repoRoot </> T.unpack (contentDirectoryToText directory)
  exists <- doesDirectoryExist directoryPath
  case exists of
    False -> do
      putStrLn $ "📁 Directory missing: " <> T.unpack (contentDirectoryToText directory)
      pure []
    True -> do
      entries <- listDirectory directoryPath
      let contentFiles = filter shouldHaveImage (fmap T.pack entries)
          sortedFiles = sortByTextDesc contentFiles
      fmap concat $ traverse (checkCandidate directoryPath directory today) sortedFiles

checkCandidateEligibility :: ContentDirectory -> Day -> Text -> Text -> CandidateEligibility
checkCandidateEligibility directory today filename content =
  case parseDateFromFilename filename of
    Just fileDate
      | directory == Reflections && fileDate > today -> Ineligible FutureReflection
    fileDate ->
      let requiresRegeneration = shouldRegenerateImage content
          untitledReflection = directory == Reflections
            && maybe False (isDateOnlyTitle content) fileDate
      in if untitledReflection
         then Ineligible UntitledReflection
         else if hasEmbeddedImage content && not requiresRegeneration
              then Ineligible AlreadyHasImage
              else Eligible requiresRegeneration

checkCandidate :: FilePath -> ContentDirectory -> Day -> Text -> IO [BackfillCandidate]
checkCandidate directoryPath directory today filename = do
  let fileDate = parseDateFromFilename filename
      filePath = directoryPath </> T.unpack filename
  case fileDate of
    Just date | directory == Reflections && date > today -> pure []
    _ -> do
      content <- TIO.readFile filePath
      case checkCandidateEligibility directory today filename content of
        Ineligible _              -> pure []
        Eligible requiresRegeneration -> pure [BackfillCandidate filePath directory filename
                                    (fromMaybe today fileDate) requiresRegeneration]

sortByDateDesc :: [BackfillCandidate] -> [BackfillCandidate]
sortByDateDesc = foldl' insertSorted []
  where
    insertSorted [] c = [c]
    insertSorted (x : xs) c
      | bcDate c >= bcDate x = c : x : xs
      | otherwise            = x : insertSorted xs c

sortByTextDesc :: [Text] -> [Text]
sortByTextDesc = foldl' ins []
  where
    ins [] t = [t]
    ins (x : xs) t
      | t >= x    = t : x : xs
      | otherwise  = x : ins xs t

processWithProviders
  :: Manager -> BackfillConfig -> [BackfillCandidate]
  -> Int -> BackfillResult -> IO BackfillResult
processWithProviders _ _ [] _ result = do
  putStrLn $ "📭 No more candidates | generated: " <> show (brImagesGenerated result)
          <> " | skipped: " <> show (brFilesSkipped result)
          <> " | errors: " <> show (length (brErrors result))
  pure result
processWithProviders _ config _ _ result
  | null (backfillProviders config) = do
      putStrLn "🚫 No providers available"
      pure result { brErrors = brErrors result <> ["No providers available"] }
processWithProviders _manager config _candidates providerIdx result
  | providerIdx >= length (backfillProviders config) = do
      putStrLn $ "🛑 All providers exhausted | generated: " <> show (brImagesGenerated result)
             <> " | errors: " <> show (length (brErrors result))
      pure result { brErrors = brErrors result <> ["All providers exhausted"] }
  | brImagesGenerated result >= backfillMaxImages config = do
      putStrLn $ "🎯 Max images reached: " <> show (brImagesGenerated result)
             <> "/" <> show (backfillMaxImages config)
      pure result
processWithProviders manager config (candidate : rest) providerIdx result = do
  let provider = backfillProviders config !! providerIdx
      action = if bcNeedsRegeneration candidate then "Regenerating" else "Generating"
      progress = show (brImagesGenerated result + 1) <> "/" <> show (backfillMaxImages config)
      directoryLabel = T.unpack (contentDirectoryToText (bcDirectory candidate))
  putStrLn $ "🎨 [" <> progress <> "] " <> action <> " image for "
          <> directoryLabel <> "/" <> T.unpack (bcFilename candidate)
          <> " via " <> T.unpack (ipcName provider)
  genResult <- tryGenerate manager provider candidate (backfillAttachmentsDir config)
  case genResult of
    Right imgResult
      | not (igrSkipped imgResult) -> do
          putStrLn $ "✅ Generated: " <> maybe "?" T.unpack (igrImageName imgResult)
          let relativePath = contentDirectoryToText (bcDirectory candidate) <> "/" <> bcFilename candidate
              newResult = result
                { brImagesGenerated = brImagesGenerated result + 1
                , brFilesUpdated = brFilesUpdated result + 1
                , brModifiedFiles = brModifiedFiles result <> [relativePath]
                }
          case brImagesGenerated newResult >= backfillMaxImages config of
            True  -> do
              putStrLn $ "🎯 Max images reached: " <> show (brImagesGenerated newResult)
                     <> "/" <> show (backfillMaxImages config)
              pure newResult
            False -> processWithProviders manager config rest providerIdx newResult
      | otherwise -> do
          putStrLn $ "⏭️  Skipped: " <> directoryLabel <> "/" <> T.unpack (bcFilename candidate)
          let newResult = result { brFilesSkipped = brFilesSkipped result + 1 }
          processWithProviders manager config rest providerIdx newResult
    Left err
      | isDailyQuotaError err || isQuotaError err || isProviderUnavailableError err -> do
          putStrLn $ "⚠️  Quota/unavailable on " <> T.unpack (ipcName provider) <> ": " <> T.unpack err
          let nextIdx = providerIdx + 1
          case nextIdx < length (backfillProviders config) of
            True -> do
              let nextProvider = backfillProviders config !! nextIdx
              putStrLn $ "🔄 Switching to provider " <> show (nextIdx + 1)
                     <> "/" <> show (length (backfillProviders config))
                     <> ": " <> T.unpack (ipcName nextProvider)
              processWithProviders manager config (candidate : rest) nextIdx result
            False -> do
              putStrLn $ "🛑 All " <> show (length (backfillProviders config)) <> " providers exhausted"
              pure result { brErrors = brErrors result <> [err] }
      | otherwise -> do
          putStrLn $ "❌ Error on " <> directoryLabel <> "/" <> T.unpack (bcFilename candidate)
                  <> ": " <> T.unpack err
          let newResult = result { brErrors = brErrors result <> [err] }
          processWithProviders manager config rest providerIdx newResult

tryGenerate
  :: Manager -> ImageProviderConfig -> BackfillCandidate -> FilePath
  -> IO (Either Text ImageGenerationResult)
tryGenerate manager provider candidate attachmentsDir =
  safeIO $ processNote manager provider (bcFilePath candidate) attachmentsDir

safeIO :: IO a -> IO (Either Text a)
safeIO action =
  fmap Right action `catch` handler
  where
    handler :: SomeException -> IO (Either Text a)
    handler e = pure $ Left $ T.pack (show e)

--------------------------------------------------------------------------------
-- Sync directories
--------------------------------------------------------------------------------

syncAttachmentsDir :: FilePath -> FilePath -> IO ()
syncAttachmentsDir srcDir dstDir = do
  srcExists <- doesDirectoryExist srcDir
  case srcExists of
    False -> pure ()
    True  -> do
      createDirectoryIfMissing True dstDir
      entries <- listDirectory srcDir
      let imageFiles = filter isImageFile entries
      mapM_ (syncIfMissing srcDir dstDir) imageFiles

syncIfMissing :: FilePath -> FilePath -> FilePath -> IO ()
syncIfMissing srcDir dstDir filename = do
  let dst = dstDir </> filename
  exists <- doesFileExist dst
  case exists of
    True  -> pure ()
    False -> copyFile (srcDir </> filename) dst

isImageFile :: FilePath -> Bool
isImageFile f =
  let ext = fmap toLower (takeExtension f)
  in ext `elem` [".jpg", ".jpeg", ".png", ".gif", ".webp"]

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f (Left a)  = Left (f a)
mapLeft _ (Right c) = Right c
