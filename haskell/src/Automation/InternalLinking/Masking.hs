{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.Masking
  ( maskProtectedRegions
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Text.Regex.TDFA ((=~))

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
        (frontmatter, rest) ->
          let fmBlock = "---\n" <> frontmatter <> "\n---\n"
              afterBlock = T.drop (T.length "\n---\n") rest
          in T.replicate (T.length fmBlock) " " <> afterBlock

maskFencedCode :: Text -> Text
maskFencedCode = maskBetweenFences

maskBetweenFences :: Text -> Text
maskBetweenFences = go
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
maskMdLinks = go
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
maskWikiL = go
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
maskBold = go
  where
    go txt =
      case T.breakOn "**" txt of
        (_, "") -> txt
        (before, rest) ->
          before <> "  " <> go (T.drop 2 rest)

replaceAllRegex :: String -> Text -> Text
replaceAllRegex pat = go
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
