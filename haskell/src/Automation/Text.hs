{-# LANGUAGE OverloadedStrings #-}

module Automation.Text
  ( countGraphemes
  , truncateToGraphemeLimit
  , calculatePostLength
  , validatePostLength
  , fitPostToLimit
  , wordJaccardSimilarity
  , stripCodeFences
  , stripEmojis
  , isEmoji
  , isEmojiOrSpace
  ) where

import Data.Maybe (fromMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import Automation.Platform (PlatformLimits (..))

countGraphemes :: Text -> Int
countGraphemes = T.length

truncateToGraphemeLimit :: Text -> Int -> Text
truncateToGraphemeLimit text maxGraphemes
  | T.length text <= maxGraphemes = text
  | otherwise = T.take (maxGraphemes - 1) text <> "…"

urlPattern :: Text -> Bool
urlPattern t = "http://" `T.isPrefixOf` t || "https://" `T.isPrefixOf` t

extractUrls :: Text -> [Text]
extractUrls = concatMap (takeWhile (not . T.null) . extractFromWord) . T.words
  where
    extractFromWord w
      | urlPattern w = [w]
      | otherwise    = []

calculatePostLength :: PlatformLimits -> Text -> Int
calculatePostLength limits text =
  case platformUrlCountLength limits of
    Nothing -> T.length text
    Just urlLen ->
      let urls = extractUrls text
          urlLengthDelta = sum (fmap (\url -> urlLen - T.length url) urls)
      in T.length text + urlLengthDelta

validatePostLength :: PlatformLimits -> Text -> (Bool, Int)
validatePostLength limits text =
  let postLength = calculatePostLength limits text
  in (postLength <= platformMaxCharacters limits, postLength)

findLastIndex :: (a -> Int -> Bool) -> [a] -> Int
findLastIndex predicate elements = go (length elements - 1) (reverse elements)
  where
    go _ []     = -1
    go i (y:ys)
      | predicate y i = i
      | otherwise     = go (i - 1) ys

rebuildPost :: [Text] -> Int -> Text -> Text -> [Text] -> Text
rebuildPost contentLines topicIndex newTopicLine urlLine trailingLines =
  let updated = take topicIndex contentLines
             <> [newTopicLine]
             <> drop (topicIndex + 1) contentLines
  in T.intercalate "\n" (updated <> [urlLine] <> trailingLines)

removeAt :: Int -> [a] -> [a]
removeAt index elements = take index elements <> drop (index + 1) elements

fitPostToLimit :: Text -> Int -> Text
fitPostToLimit text maxGraphemes
  | countGraphemes text <= maxGraphemes = text
  | otherwise = fitWithStrategies (T.splitOn "\n" text) maxGraphemes

fitWithStrategies :: [Text] -> Int -> Text
fitWithStrategies contentLines maxGraphemes =
  let urlLineIndex = findLastIndex (\l _ -> urlPattern l) contentLines
  in case urlLineIndex of
    i | i < 0 -> truncateToGraphemeLimit (T.intercalate "\n" contentLines) maxGraphemes
    urlIndex ->
      let urlLine     = contentLines !! urlIndex
          preUrlLines = take urlIndex contentLines
          trailingLines = drop (urlIndex + 1) contentLines
          topicIndex    = findLastIndex (\l i -> i > 0 && " | " `T.isInfixOf` l) preUrlLines
      in tryStrategies preUrlLines topicIndex urlLine trailingLines maxGraphemes

tryStrategies :: [Text] -> Int -> Text -> [Text] -> Int -> Text
tryStrategies contentLines topicIndex urlLine trailingLines maxGraphemes =
  let allLines = contentLines <> [urlLine] <> trailingLines
      originalText = T.intercalate "\n" allLines
  in fromMaybe (truncateToGraphemeLimit originalText maxGraphemes)
       $  strategy1 contentLines topicIndex urlLine trailingLines maxGraphemes
      <|> strategy2 contentLines topicIndex urlLine trailingLines maxGraphemes
      <|> strategy3 contentLines topicIndex urlLine trailingLines maxGraphemes
      <|> strategy4 contentLines topicIndex urlLine trailingLines maxGraphemes
      <|> strategy5 contentLines urlLine trailingLines maxGraphemes

strategy1 :: [Text] -> Int -> Text -> [Text] -> Int -> Maybe Text
strategy1 contentLines topicIndex urlLine trailingLines maxGraphemes
  | topicIndex < 0 = Nothing
  | otherwise =
      let topicLine = contentLines !! topicIndex
          tags = T.splitOn " | " topicLine
      in tryRemovingTags contentLines topicIndex tags urlLine trailingLines maxGraphemes

tryRemovingTags :: [Text] -> Int -> [Text] -> Text -> [Text] -> Int -> Maybe Text
tryRemovingTags _ _ [] _ _ _ = Nothing
tryRemovingTags _ _ [_] _ _ _ = Nothing
tryRemovingTags contentLines topicIndex tags urlLine trailingLines maxGraphemes =
  let shortened = init tags
      candidate = rebuildPost contentLines topicIndex (T.intercalate " | " shortened) urlLine trailingLines
  in if countGraphemes candidate <= maxGraphemes
     then Just candidate
     else tryRemovingTags contentLines topicIndex shortened urlLine trailingLines maxGraphemes

strategy2 :: [Text] -> Int -> Text -> [Text] -> Int -> Maybe Text
strategy2 contentLines topicIndex urlLine trailingLines maxGraphemes
  | topicIndex < 0 = Nothing
  | otherwise =
      let trimmed = removeAt topicIndex contentLines
          trimmed' = if topicIndex > 0 && topicIndex - 1 < length trimmed
                        && (trimmed !! (topicIndex - 1)) == ""
                     then removeAt (topicIndex - 1) trimmed
                     else trimmed
          candidate = T.intercalate "\n" (trimmed' <> [urlLine] <> trailingLines)
      in if countGraphemes candidate <= maxGraphemes
         then Just candidate
         else Nothing

strategy3 :: [Text] -> Int -> Text -> [Text] -> Int -> Maybe Text
strategy3 contentLines topicIndex urlLine trailingLines maxGraphemes =
  let workingLines = removeTopicLine contentLines topicIndex
      titleLine = safeHead "" workingLines
      colonPosition = T.findIndex (== ':') titleLine
  in case colonPosition of
       Just colonIndex | colonIndex > 0 ->
         let shortTitle = T.strip (T.take colonIndex titleLine)
         in if T.null shortTitle
            then Nothing
            else let updated = shortTitle : drop 1 workingLines
                     candidate = T.intercalate "\n" (updated <> [urlLine] <> trailingLines)
                 in if countGraphemes candidate <= maxGraphemes
                    then Just candidate
                    else Nothing
       _ -> Nothing

strategy4 :: [Text] -> Int -> Text -> [Text] -> Int -> Maybe Text
strategy4 contentLines topicIndex urlLine trailingLines maxGraphemes =
  let workingLines = removeTopicLine contentLines topicIndex
  in case workingLines of
       [] -> Nothing
       (_:rest) ->
         let noTitle = case rest of
               ("":elements) -> elements
               elements      -> elements
             candidate = T.intercalate "\n" (noTitle <> [urlLine] <> trailingLines)
         in if countGraphemes candidate <= maxGraphemes
            then Just candidate
            else Nothing

strategy5 :: [Text] -> Text -> [Text] -> Int -> Maybe Text
strategy5 contentLines urlLine _trailingLines maxGraphemes =
  let separatorAndUrl = "\n" <> urlLine
      reservedGraphemes = countGraphemes separatorAndUrl
      available = maxGraphemes - reservedGraphemes
  in if available > 1
     then let contentText = T.intercalate "\n" contentLines
          in Just (truncateToGraphemeLimit contentText available <> separatorAndUrl)
     else Nothing

removeTopicLine :: [Text] -> Int -> [Text]
removeTopicLine contentLines topicIndex
  | topicIndex < 0 = contentLines
  | otherwise =
      let trimmed = removeAt topicIndex contentLines
      in if topicIndex > 0 && topicIndex - 1 < length trimmed
            && (trimmed !! (topicIndex - 1)) == ""
         then removeAt (topicIndex - 1) trimmed
         else trimmed

safeHead :: a -> [a] -> a
safeHead def []    = def
safeHead _ (x:_) = x

(<|>) :: Maybe a -> Maybe a -> Maybe a
Nothing <|> r = r
l@(Just _) <|> _ = l
infixl 3 <|>

-- | Word-based Jaccard similarity between two texts.
--
--   Splits both texts into word sets and computes |A ∩ B| / |A ∪ B|.
--   Returns 1.0 for two empty texts, 0.0 when one is empty and the other is not.
--
--   Empirically tested on ai-blog corpus:
--     genuinely new posts score ≤ 0.10 against all vault files
--     modified/renamed versions score ≥ 0.39
--   Threshold of 0.25 sits in the middle of a 0.29-wide gap.
wordJaccardSimilarity :: Text -> Text -> Double
wordJaccardSimilarity a b =
  let wordsA = wordSet a
      wordsB = wordSet b
      intersectionSize = Set.size (Set.intersection wordsA wordsB)
      unionSize = Set.size (Set.union wordsA wordsB)
  in case unionSize of
       0 -> 1.0
       n -> fromIntegral intersectionSize / fromIntegral n

wordSet :: Text -> Set Text
wordSet = Set.fromList . T.words . T.toCaseFold

stripCodeFences :: Text -> Text
stripCodeFences text =
  let withoutPrefix = case T.stripPrefix "```markdown\n" text of
        Just rest -> rest
        Nothing -> case T.stripPrefix "```md\n" text of
          Just rest -> rest
          Nothing -> fromMaybe text (T.stripPrefix "```\n" text)
  in fromMaybe withoutPrefix (T.stripSuffix "\n```" withoutPrefix)

-- Unicode TR#51 Extended_Pictographic property.
-- Consolidated ranges from emoji-data.txt (Unicode 17.0, 2025-07-25).
-- Source: https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
isEmoji :: Char -> Bool
isEmoji c =
  c == '\x00A9' || c == '\x00AE'
    || c == '\x203C' || c == '\x2049'
    || c == '\x2122' || c == '\x2139'
    || (c >= '\x2194' && c <= '\x21AA')
    || (c >= '\x231A' && c <= '\x23FA')
    || c == '\x24C2'
    || (c >= '\x25AA' && c <= '\x25FE')
    || (c >= '\x2600' && c <= '\x27BF')
    || (c >= '\x2934' && c <= '\x2935')
    || (c >= '\x2B05' && c <= '\x2B55')
    || c == '\x3030' || c == '\x303D' || c == '\x3297' || c == '\x3299'
    || (c >= '\x1F000' && c <= '\x1FFFD')

isEmojiOrSpace :: Char -> Bool
isEmojiOrSpace c =
  c == ' '
    || c == '\x200D'
    || c == '\xFE0F'
    || isEmoji c

stripEmojis :: Text -> Text
stripEmojis =
  T.intercalate " "
    . filter (not . T.null)
    . T.split (== ' ')
    . T.filter (not . isEmoji)
