{-# LANGUAGE OverloadedStrings #-}

module Automation.Text
  ( countGraphemes
  , truncateToGraphemeLimit
  , calculateTweetLength
  , validateTweetLength
  , fitPostToLimit
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Automation.Types (twitterMaxLength, twitterUrlLength)

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

calculateTweetLength :: Text -> Int
calculateTweetLength text =
  let urls = extractUrls text
      urlLengthDelta = sum (fmap (\url -> twitterUrlLength - T.length url) urls)
  in T.length text + urlLengthDelta

validateTweetLength :: Text -> (Bool, Int)
validateTweetLength text =
  let len = calculateTweetLength text
  in (len <= twitterMaxLength, len)

findLastIndex :: (a -> Int -> Bool) -> [a] -> Int
findLastIndex p xs = go (length xs - 1) (reverse xs)
  where
    go _ []     = -1
    go i (y:ys)
      | p y i    = i
      | otherwise = go (i - 1) ys

rebuildPost :: [Text] -> Int -> Text -> Text -> [Text] -> Text
rebuildPost contentLines topicIndex newTopicLine urlLine trailingLines =
  let updated = take topicIndex contentLines
             <> [newTopicLine]
             <> drop (topicIndex + 1) contentLines
  in T.intercalate "\n" (updated <> [urlLine] <> trailingLines)

removeAt :: Int -> [a] -> [a]
removeAt i xs = take i xs <> drop (i + 1) xs

fitPostToLimit :: Text -> Int -> Text
fitPostToLimit text maxGraphemes
  | countGraphemes text <= maxGraphemes = text
  | otherwise = fitWithStrategies (T.splitOn "\n" text) maxGraphemes

fitWithStrategies :: [Text] -> Int -> Text
fitWithStrategies lns maxGraphemes =
  let urlLineIndex = findLastIndex (\l _ -> urlPattern l) lns
  in case urlLineIndex of
    i | i < 0 -> truncateToGraphemeLimit (T.intercalate "\n" lns) maxGraphemes
    urlIdx ->
      let urlLine       = lns !! urlIdx
          contentLines  = take urlIdx lns
          trailingLines = drop (urlIdx + 1) lns
          topicIndex    = findLastIndex (\l i -> i > 0 && " | " `T.isInfixOf` l) contentLines
      in tryStrategies contentLines topicIndex urlLine trailingLines maxGraphemes

tryStrategies :: [Text] -> Int -> Text -> [Text] -> Int -> Text
tryStrategies contentLines topicIndex urlLine trailingLines maxGraphemes =
  let allLines = contentLines <> [urlLine] <> trailingLines
      originalText = T.intercalate "\n" allLines
  in maybe (truncateToGraphemeLimit originalText maxGraphemes) id
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
      colonIdx = T.findIndex (== ':') titleLine
  in case colonIdx of
       Just ci | ci > 0 ->
         let shortTitle = T.strip (T.take ci titleLine)
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
               ("":xs) -> xs
               xs      -> xs
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
