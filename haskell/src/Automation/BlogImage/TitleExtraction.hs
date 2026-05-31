module Automation.BlogImage.TitleExtraction
  ( extractTitle
  , extractTitleFromFrontmatter
  , findH1Title
  , stripQuotes
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

extractTitle :: Text -> Text
extractTitle content =
  let ls = T.splitOn "\n" content
      fromFrontmatter = extractTitleFromFrontmatter ls False
      fromH1 = findH1Title ls
  in fromMaybe "" (fromFrontmatter <|> fromH1)
  where
    (<|>) :: Maybe a -> Maybe a -> Maybe a
    (<|>) (Just x) _ = Just x
    (<|>) Nothing  y = y

extractTitleFromFrontmatter :: [Text] -> Bool -> Maybe Text
extractTitleFromFrontmatter [] _ = Nothing
extractTitleFromFrontmatter (line : rest) inFm
  | T.strip line == "---" = if inFm then Nothing else extractTitleFromFrontmatter rest True
  | inFm = case T.stripPrefix "title:" line of
      Just val -> Just (stripQuotes (T.strip val))
      Nothing  -> extractTitleFromFrontmatter rest True
  | otherwise = Nothing

findH1Title :: [Text] -> Maybe Text
findH1Title = foldr (\line accumulated -> if "# " `T.isPrefixOf` line then Just (T.strip (T.drop 2 line)) else accumulated) Nothing

stripQuotes :: Text -> Text
stripQuotes t =
  let stripped = case T.uncons t of
        Just (character, rest) | character == '"' || character == '\'' -> rest
        _ -> t
  in case T.unsnoc stripped of
    Just (init', character) | character == '"' || character == '\'' -> init'
    _ -> stripped
