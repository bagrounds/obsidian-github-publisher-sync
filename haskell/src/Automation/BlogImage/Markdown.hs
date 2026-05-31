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
  let contentLines = T.splitOn "\n" content
      embed = "![[attachments/" <> imageName <> "]]"
      insertAfterH1 [] = []
      insertAfterH1 (line : rest)
        | "# " `T.isPrefixOf` line = line : embed : rest
        | otherwise              = line : insertAfterH1 rest
  in T.intercalate "\n" (insertAfterH1 contentLines)

removeImageEmbed :: Text -> (Text, Maybe Text)
removeImageEmbed content =
  let string = T.unpack content
      pat = "^!\\[\\[(attachments/)?([^]]+\\.(jpg|jpeg|png|gif|webp))\\]\\]" :: String
      matches = string =~ pat :: [[String]]
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
stripAttachmentsPrefix text = fromMaybe text (T.stripPrefix "attachments/" text)

collapseNewlines :: Text -> Text
collapseNewlines = collapseStep
  where
    collapseStep text = let collapsed = T.replace "\n\n\n" "\n\n" text
                        in if collapsed == text then text else collapseStep collapsed

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
    stripHeading line
      | "######" `T.isPrefixOf` line = T.stripStart (T.drop 6 line)
      | "#####" `T.isPrefixOf` line  = T.stripStart (T.drop 5 line)
      | "####" `T.isPrefixOf` line   = T.stripStart (T.drop 4 line)
      | "###" `T.isPrefixOf` line    = T.stripStart (T.drop 3 line)
      | "##" `T.isPrefixOf` line     = T.stripStart (T.drop 2 line)
      | "#" `T.isPrefixOf` line      = T.stripStart (T.drop 1 line)
      | otherwise                 = line

removeObsidianEmbeds :: Text -> Text
removeObsidianEmbeds text =
  let string = T.unpack text
      result = replaceAll string "!\\[\\[[^]]*\\]\\]" ""
  in T.pack result

removeMarkdownImages :: Text -> Text
removeMarkdownImages text =
  let string = T.unpack text
      result = replaceAll string "!\\[[^]]*\\]\\([^)]*\\)" ""
  in T.pack result

removeMarkdownLinks :: Text -> Text
removeMarkdownLinks text =
  let string = T.unpack text
      result = replaceAllWith string "\\[([^]]*)\\]\\([^)]*\\)" (\case
        (_full : captured : _) -> captured
        [full]                 -> full
        _                      -> "")
  in T.pack result

removeCodeBlocks :: Text -> Text
removeCodeBlocks content = T.intercalate "\n" (processLines (T.lines content) False)
  where
    processLines [] _ = []
    processLines (line : rest) inBlock
      | "```" `T.isPrefixOf` line && inBlock = processLines rest False
      | "```" `T.isPrefixOf` line            = processLines rest True
      | inBlock                            = processLines rest True
      | otherwise                          = line : processLines rest False

removeInlineCode :: Text -> Text
removeInlineCode text =
  let string = T.unpack text
      result = replaceAll string "`[^`]*`" ""
  in T.pack result

removeEmphasis :: Text -> Text
removeEmphasis = T.filter (`notElem` ['*', '_', '~'])

removeUnorderedLists :: Text -> Text
removeUnorderedLists = T.unlines . fmap stripBullet . T.lines
  where
    stripBullet line
      | matchesBullet line = T.stripStart (T.drop 2 (T.stripStart line))
      | otherwise       = line
    matchesBullet line =
      let stripped = T.stripStart line
      in case T.uncons stripped of
           Just (character, rest) | character `elem` ['-', '*', '+'] -> case T.uncons rest of
             Just (' ', _) -> True
             _             -> False
           _ -> False

removeOrderedLists :: Text -> Text
removeOrderedLists = T.unlines . fmap stripOrdered . T.lines
  where
    stripOrdered line =
      let stripped = T.stripStart line
          (digits, rest) = T.span isDigit stripped
      in if not (T.null digits)
         then case T.uncons rest of
           Just ('.', afterDot) -> case T.uncons afterDot of
             Just (' ', content') -> T.stripStart content'
             _                    -> line
           _ -> line
         else line

removeBlockquotes :: Text -> Text
removeBlockquotes = T.unlines . fmap stripQuote . T.lines
  where
    stripQuote line =
      let stripped = T.stripStart line
      in case T.uncons stripped of
           Just ('>', rest) -> T.stripStart rest
           _                -> line

removeTableCells :: Text -> Text
removeTableCells text =
  let string = T.unpack text
      result = replaceAll string "\\|[^|\\n]*\\|" ""
  in T.pack result

removeTableSeparators :: Text -> Text
removeTableSeparators = T.unlines . filter (not . isTableSep) . T.lines
  where
    isTableSep line = T.all (\character -> character == '-' || character == '|' || character == ':' || character == ' ') (T.strip line)
                   && T.length (T.strip line) > 2
                   && T.isInfixOf "-" line

collapseTripleNewlines :: Text -> Text
collapseTripleNewlines text =
  let collapsed = T.replace "\n\n\n" "\n\n" text
  in if collapsed == text then text else collapseTripleNewlines collapsed

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
