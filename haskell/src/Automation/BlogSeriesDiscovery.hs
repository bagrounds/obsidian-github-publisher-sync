module Automation.BlogSeriesDiscovery
  ( DiscoveredSeries (..)
  , DiscoveryError (..)
  , parseDhallConfig
  , discoverSeries
  , deriveBlogSeriesConfig
  , deriveBlogSeriesRunConfig
  , deriveScheduleEntry
  , deriveTaskId
  , derivePriorityUserEnvVar
  , deriveAuthor
  , deriveBaseUrl
  , deriveNavLink
  , configDirectoryName
  ) where

import Data.Char (isAlphaNum, isDigit)
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>), dropExtension, takeExtension)
import Text.Parsec
  ( ParseError
  , between
  , char
  , eof
  , many
  , many1
  , noneOf
  , oneOf
  , optionMaybe
  , parse
  , satisfy
  , sepBy
  , spaces
  , string
  , try
  , (<|>)
  )
import Text.Parsec.Text (Parser)

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Scheduler (BlogSeriesRunConfig (..), ScheduleEntry (..), TaskId (..))

configDirectoryName :: FilePath
configDirectoryName = "series"

data DiscoveredSeries = DiscoveredSeries
  { dsId                 :: Text
  , dsName               :: Text
  , dsIcon               :: Text
  , dsPriorityUser       :: Maybe Text
  , dsScheduleHourPacific :: Int
  , dsModels             :: NonEmpty Gemini.Model
  , dsPostTimeUtc        :: Text
  } deriving (Show, Eq)

data DiscoveryError
  = ParseError FilePath ParseError
  | ValidationError FilePath Text
  deriving (Show)

data RawConfig = RawConfig
  { rcName               :: Maybe Text
  , rcIcon               :: Maybe Text
  , rcPriorityUser       :: Maybe (Maybe Text)
  , rcScheduleHourPacific :: Maybe Int
  , rcModels             :: Maybe [Text]
  , rcPostTimeUtc        :: Maybe Text
  }

emptyRawConfig :: RawConfig
emptyRawConfig = RawConfig Nothing Nothing Nothing Nothing Nothing Nothing

discoverSeries :: FilePath -> IO (Either [DiscoveryError] [DiscoveredSeries])
discoverSeries baseDir = do
  let seriesDir = baseDir </> configDirectoryName
  exists <- doesDirectoryExist seriesDir
  if not exists
    then pure (Right [])
    else do
      entries <- listDirectory seriesDir
      let dhallFiles = filter isDhallFile entries
      results <- traverse (parseSeriesFile seriesDir) dhallFiles
      let errors = concatMap (\case Left errs -> errs; Right _ -> []) results
          successes = concatMap (\case Right series -> [series]; Left _ -> []) results
      if null errors
        then pure (Right (sortOn dsId successes))
        else pure (Left errors)

isDhallFile :: FilePath -> Bool
isDhallFile path = takeExtension path == ".dhall"

parseSeriesFile :: FilePath -> FilePath -> IO (Either [DiscoveryError] DiscoveredSeries)
parseSeriesFile seriesDir filename = do
  let filePath = seriesDir </> filename
      seriesId = T.pack (dropExtension filename)
  content <- TIO.readFile filePath
  pure $ case parseDhallConfig content of
    Left parseError -> Left [ParseError filePath parseError]
    Right rawConfig -> case validateRawConfig filePath seriesId rawConfig of
      Left validationErrors -> Left validationErrors
      Right discovered -> Right discovered

parseDhallConfig :: Text -> Either ParseError RawConfig
parseDhallConfig = parse dhallRecord "series config"

validateRawConfig :: FilePath -> Text -> RawConfig -> Either [DiscoveryError] DiscoveredSeries
validateRawConfig filePath seriesId RawConfig{..} =
  let errors = concat
        [ maybe [ValidationError filePath "missing required field: name"] (const []) rcName
        , maybe [ValidationError filePath "missing required field: icon"] (const []) rcIcon
        , maybe [ValidationError filePath "missing required field: scheduleHourPacific"] (const []) rcScheduleHourPacific
        , maybe [ValidationError filePath "missing required field: models"] (const []) rcModels
        , maybe [ValidationError filePath "missing required field: postTimeUtc"] (const []) rcPostTimeUtc
        , case rcScheduleHourPacific of
            Just hour | hour < 0 || hour > 23 ->
              [ValidationError filePath ("scheduleHourPacific must be 0-23, got: " <> T.pack (show hour))]
            _ -> []
        , case rcModels of
            Just [] -> [ValidationError filePath "models list must not be empty"]
            _ -> []
        ]
  in if null errors
    then case (rcName, rcIcon, rcScheduleHourPacific, rcModels, rcPostTimeUtc) of
      (Just name, Just icon, Just hour, Just (firstModel : restModels), Just postTime) ->
        Right DiscoveredSeries
          { dsId = seriesId
          , dsName = name
          , dsIcon = icon
          , dsPriorityUser = fromMaybe Nothing rcPriorityUser
          , dsScheduleHourPacific = hour
          , dsModels = Gemini.modelFromText firstModel :| fmap Gemini.modelFromText restModels
          , dsPostTimeUtc = postTime
          }
      _ -> Left errors
    else Left errors

deriveBlogSeriesConfig :: DiscoveredSeries -> BlogSeriesConfig
deriveBlogSeriesConfig DiscoveredSeries{..} = BlogSeriesConfig
  { bscId = dsId
  , bscName = dsName
  , bscIcon = dsIcon
  , bscAuthor = deriveAuthor dsId
  , bscBaseUrl = deriveBaseUrl dsId
  , bscPriorityUser = dsPriorityUser
  , bscNavLink = deriveNavLink dsId dsIcon dsName
  , bscPostTimeUtc = dsPostTimeUtc
  }

deriveBlogSeriesRunConfig :: DiscoveredSeries -> BlogSeriesRunConfig
deriveBlogSeriesRunConfig DiscoveredSeries{..} = BlogSeriesRunConfig
  { bsrcSeriesId = dsId
  , bsrcModelChain = dsModels
  , bsrcPriorityUserEnvVar = derivePriorityUserEnvVar dsId
  }

deriveScheduleEntry :: DiscoveredSeries -> ScheduleEntry
deriveScheduleEntry DiscoveredSeries{..} = ScheduleEntry
  { seTaskId = deriveTaskId dsId
  , seHoursPacific = [dsScheduleHourPacific]
  , seAtOrAfter = False
  }

deriveTaskId :: Text -> TaskId
deriveTaskId = BlogSeries

deriveAuthor :: Text -> Text
deriveAuthor seriesId = "[[" <> seriesId <> "]]"

deriveBaseUrl :: Text -> Text
deriveBaseUrl seriesId = "https://bagrounds.org/" <> seriesId

deriveNavLink :: Text -> Text -> Text -> Text
deriveNavLink seriesId icon name =
  "[[index|Home]] > [[" <> seriesId <> "/index|" <> icon <> " " <> name <> "]]"

derivePriorityUserEnvVar :: Text -> Text
derivePriorityUserEnvVar seriesId =
  T.map toEnvChar (T.toUpper seriesId) <> "_PRIORITY_USER"
  where
    toEnvChar '-' = '_'
    toEnvChar c   = c

-- ---------------------------------------------------------------------------
-- Dhall record parser (Parsec-based, subset of Dhall syntax)
-- ---------------------------------------------------------------------------

dhallRecord :: Parser RawConfig
dhallRecord = do
  spaces
  _ <- lineComments
  _ <- char '{'
  fields <- dhallField `sepBy` fieldSeparator
  spaces
  _ <- lineComments
  _ <- char '}'
  spaces
  _ <- lineComments
  eof
  pure (foldr applyField emptyRawConfig fields)

lineComments :: Parser ()
lineComments = do
  _ <- many (try singleLineComment)
  pure ()

singleLineComment :: Parser ()
singleLineComment = do
  spaces
  _ <- string "--"
  _ <- many (noneOf "\n")
  _ <- oneOf "\n"
  pure ()

fieldSeparator :: Parser ()
fieldSeparator = do
  spaces
  _ <- lineComments
  _ <- char ','
  spaces
  _ <- lineComments
  pure ()

data DhallField
  = FieldName Text
  | FieldIcon Text
  | FieldPriorityUser (Maybe Text)
  | FieldScheduleHourPacific Int
  | FieldModels [Text]
  | FieldPostTimeUtc Text

applyField :: DhallField -> RawConfig -> RawConfig
applyField field config = case field of
  FieldName value -> config { rcName = Just value }
  FieldIcon value -> config { rcIcon = Just value }
  FieldPriorityUser value -> config { rcPriorityUser = Just value }
  FieldScheduleHourPacific value -> config { rcScheduleHourPacific = Just value }
  FieldModels value -> config { rcModels = Just value }
  FieldPostTimeUtc value -> config { rcPostTimeUtc = Just value }

dhallField :: Parser DhallField
dhallField = do
  spaces
  _ <- lineComments
  fieldName <- many1 (satisfy (\c -> isAlphaNum c || c == '_'))
  spaces
  _ <- char '='
  spaces
  case fieldName of
    "name"               -> FieldName <$> dhallString
    "icon"               -> FieldIcon <$> dhallString
    "priorityUser"       -> FieldPriorityUser <$> dhallOptionalText
    "scheduleHourPacific" -> FieldScheduleHourPacific <$> dhallInt
    "models"             -> FieldModels <$> dhallStringList
    "postTimeUtc"        -> FieldPostTimeUtc <$> dhallString
    other                -> fail ("Unknown field: " <> other)

dhallString :: Parser Text
dhallString = do
  _ <- char '"'
  content <- many (noneOf "\"\\")
  _ <- char '"'
  pure (T.pack content)

dhallInt :: Parser Int
dhallInt = do
  digits <- many1 (satisfy isDigit)
  pure (read digits)

dhallOptionalText :: Parser (Maybe Text)
dhallOptionalText =
  try dhallSome <|> dhallNone

dhallSome :: Parser (Maybe Text)
dhallSome = do
  _ <- string "Some"
  spaces
  Just <$> dhallString

dhallNone :: Parser (Maybe Text)
dhallNone = do
  _ <- string "None"
  _ <- optionMaybe (spaces >> string "Text")
  pure Nothing

dhallStringList :: Parser [Text]
dhallStringList = between (char '[' >> spaces) (spaces >> char ']') items
  where
    items = dhallString `sepBy` listSeparator
    listSeparator = do
      spaces
      _ <- char ','
      spaces
      pure ()
