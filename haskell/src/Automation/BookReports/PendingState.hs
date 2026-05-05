module Automation.BookReports.PendingState
  ( PendingState (..)
  , emptyPendingState
  , readPendingField
  , writePendingState
  , clearPendingState
  , recordCompletedToday
  ) where

import Control.Applicative ((<|>))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day)
import System.Directory (doesFileExist)

import Automation.Frontmatter (parseFrontmatter, quoteYamlValue)
import Automation.PacificTime (formatDay)
import Automation.SocialPosting.FrontmatterUpdate (upsertFrontmatterField)

import Automation.BookReports.Types
  ( Asin
  , BookTitle
  , mkAsin
  , mkBookTitle
  , unAsin
  , unBookTitle
  )

data PendingState = PendingState
  { pendingTitle       :: Maybe BookTitle
  , pendingAsin        :: Maybe Asin
  , lastGeneratedOnDay :: Maybe Day
  } deriving (Eq, Show)

emptyPendingState :: PendingState
emptyPendingState = PendingState Nothing Nothing Nothing

pendingTitleKey :: Text
pendingTitleKey = "book_report_pending"

pendingAsinKey :: Text
pendingAsinKey = "book_report_asin"

lastGeneratedKey :: Text
lastGeneratedKey = "book_report_last_generated"

readPendingField :: FilePath -> IO PendingState
readPendingField indexPath = do
  exists <- doesFileExist indexPath
  if not exists
    then pure emptyPendingState
    else do
      raw <- TIO.readFile indexPath
      let (fields, _) = parseFrontmatter raw
      pure PendingState
        { pendingTitle       = Map.lookup pendingTitleKey  fields >>= textToBookTitle
        , pendingAsin        = Map.lookup pendingAsinKey   fields >>= textToAsin
        , lastGeneratedOnDay = Map.lookup lastGeneratedKey fields >>= parseIsoDay
        }

writePendingState :: FilePath -> PendingState -> IO ()
writePendingState indexPath state =
  modifyFrontmatter indexPath
    [ (pendingTitleKey,  quoteYamlValue . unBookTitle <$> pendingTitle state)
    , (pendingAsinKey,   quoteYamlValue . unAsin      <$> pendingAsin state)
    , (lastGeneratedKey, quoteYamlValue . formatDay   <$> lastGeneratedOnDay state)
    ]

clearPendingState :: FilePath -> IO ()
clearPendingState indexPath =
  modifyFrontmatter indexPath
    [ (pendingTitleKey, Nothing)
    , (pendingAsinKey,  Nothing)
    ]

recordCompletedToday :: FilePath -> Day -> IO ()
recordCompletedToday indexPath today =
  modifyFrontmatter indexPath
    [ (pendingTitleKey,  Nothing)
    , (pendingAsinKey,   Nothing)
    , (lastGeneratedKey, Just (quoteYamlValue (formatDay today)))
    ]

modifyFrontmatter :: FilePath -> [(Text, Maybe Text)] -> IO ()
modifyFrontmatter indexPath updates = do
  exists <- doesFileExist indexPath
  if not exists
    then pure ()
    else do
      content <- TIO.readFile indexPath
      let contentLines = T.splitOn "\n" content
      case contentLines of
        (firstLine : restLines)
          | T.strip firstLine == "---" ->
              case break (\l -> T.strip l == "---") restLines of
                (_, []) -> pure ()
                (frontmatterLines, closingDash : bodyLines) -> do
                  let updated = applyFrontmatterUpdates frontmatterLines updates
                      rebuilt = T.intercalate "\n"
                                  (firstLine : updated <> [closingDash] <> bodyLines)
                  TIO.writeFile indexPath rebuilt
        _ -> pure ()

applyFrontmatterUpdates :: [Text] -> [(Text, Maybe Text)] -> [Text]
applyFrontmatterUpdates =
  foldl applySingle
  where
    applySingle frontmatter (key, Nothing) = removeField frontmatter key
    applySingle frontmatter (key, Just rendered) = upsertFrontmatterField frontmatter key rendered

removeField :: [Text] -> Text -> [Text]
removeField frontmatter key =
  filter (not . isFieldLine) frontmatter
  where
    keyPattern = key <> ":"
    isFieldLine line = T.isPrefixOf keyPattern (T.stripStart line)

textToBookTitle :: Text -> Maybe BookTitle
textToBookTitle = toMaybe . mkBookTitle . unquote

textToAsin :: Text -> Maybe Asin
textToAsin = toMaybe . mkAsin . unquote

toMaybe :: Either e a -> Maybe a
toMaybe = either (const Nothing) Just

unquote :: Text -> Text
unquote raw =
  let stripped = T.strip raw
  in fromMaybe stripped (stripPair "\"" stripped <|> stripPair "'" stripped)
  where
    stripPair quote value = do
      withoutLead <- T.stripPrefix quote value
      T.stripSuffix quote withoutLead

parseIsoDay :: Text -> Maybe Day
parseIsoDay raw =
  case reads (T.unpack (unquote raw)) of
    [(day, "")] -> Just day
    _           -> Nothing

