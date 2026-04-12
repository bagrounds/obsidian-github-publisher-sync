module Automation.BlogImage.Markdown
  ( stripMarkdownSyntax
  , removeHeadings
  , removeObsidianEmbeds
  , removeMarkdownImages
  , removeMarkdownLinks
  , removeCodeBlocks
  , removeInlineCode
  , insertImageEmbed
  , removeImageEmbed
  , cleanContentForPrompt
  , buildImagePrompt
  ) where

import Data.Char (isDigit)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Text.Regex.TDFA ((=~))

import Automation.BlogPrompt (stripEmbedSections)
import Automation.Frontmatter (parseFrontmatter)

cloudflarePromptMaxLength :: Int
cloudflarePromptMaxLength = 2048

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
      result = replaceAllWith s "\\[([^]]*)\\]\\([^)]*\\)" (\case
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
