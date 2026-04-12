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
