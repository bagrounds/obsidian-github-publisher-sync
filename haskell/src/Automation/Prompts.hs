module Automation.Prompts
  ( PromptPair (..)
  , aiQuestionPrefix
  , calculateQuestionBudget
  , stripSubtitle
  , buildTagsPrompt
  , buildQuestionPrompt
  , parseQuestionAndTags
  , assemblePost
  , buildShortenQuestionPrompt
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Automation.Types (ReflectionData (..), blueskyMaxLength)

data PromptPair = PromptPair
  { ppSystem :: Text
  , ppUser   :: Text
  } deriving (Show, Eq)

aiQuestionPrefix :: Text
aiQuestionPrefix = "#AI Q: "

topicTagsInstructions :: Text
topicTagsInstructions = T.intercalate "\n"
  [ "- Each topic tag MUST be an emoji followed by a space and a short topic label (e.g. 🌐 Systems Thinking or 🤖 AI)"
  , "- Separate tags with \" | \""
  , "- Do NOT output bare emojis separated by pipes — every tag needs a text label after the emoji"
  , "- Extract topics from the content (books, videos, concepts, themes, etc.)"
  , "- Use 2–4 concise tags"
  , "- Avoid using words that are in the title"
  , "- IMPORTANT: Keep the total tags line short — it must fit in a post under 300 characters"
  ]

calculateQuestionBudget :: ReflectionData -> Int
calculateQuestionBudget rd =
  let titleLength = T.length (rdTitle rd)
      urlLength = T.length (rdUrl rd)
      prefixLength = T.length aiQuestionPrefix
      tagLineAllowance = 60 :: Int
      fixedOverhead = titleLength + 2 + prefixLength + 2 + tagLineAllowance + 1 + urlLength
      budget = blueskyMaxLength - fixedOverhead
  in max 30 budget

stripSubtitle :: Text -> Text
stripSubtitle title =
  case T.findIndex (== ':') title of
    Nothing -> title
    Just idx ->
      let shortened = T.strip (T.take idx title)
      in case T.null shortened of
        True  -> title
        False -> shortened

buildTagsPrompt :: ReflectionData -> PromptPair
buildTagsPrompt rd =
  let system = T.intercalate "\n"
        [ "You generate emoji topic tags for a social media post promoting a blog entry from bagrounds.org."
        , ""
        , "Return ONLY a single line of emoji-prefixed topic tags. Nothing else — no title, no URL, no commentary."
        , ""
        , "Rules for topic tags:"
        , topicTagsInstructions
        , ""
        , "Examples of good output:"
        , "📚 Book Series | 🌌 Sci-Fi Exploration | 🤖 Artificial General Intelligence"
        , "🕸️ Animal Fables | 🐑 Children's Verse | 🧸 Rhyme Collections"
        , "🧪 Experimentation | 📊 Statistics | 🤖 AI Writing"
        ]
      user = T.intercalate "\n"
        [ "Generate emoji topic tags for this page:"
        , ""
        , "Title: " <> rdTitle rd
        , "URL: " <> rdUrl rd
        , "Date: " <> rdDate rd
        , ""
        , "Content:"
        , rdBody rd
        ]
  in PromptPair { ppSystem = system, ppUser = user }

buildQuestionPrompt :: ReflectionData -> PromptPair
buildQuestionPrompt rd =
  let maxChars = calculateQuestionBudget rd
      maxCharsText = T.pack (show maxChars)
      system = T.intercalate "\n"
        [ "You generate a discussion question for a social media post about a blog entry from bagrounds.org."
        , "Return ONLY a single line — the question. Nothing else — no title, no URL, no commentary, no tags, no labels."
        , ""
        , "Write a single, extremely concise question. Do not use any personal pronouns — the brief question should be 100% 2nd person. The goal of the question is to attract discussion engagement on a social media post about this content. It should be relatable and easy to answer with an opinion. Minimize word count and don't try to fake personality. Think Strunk and White for concision. Use fewer words. Never explicitly ask what's obvious implicitly (e.g. we are asking what they think, so we don't have to use the words \"what do you think\"). Never use quotation marks or hyphens. Be careful not to ask questions that are too personal. People should want to answer the question in a public forum. Also, the question should try to be relevant to the content but novel and interesting. Start the question with a single emoji. The question MUST end with a question mark."
        , ""
        , "IMPORTANT: The question MUST be at most " <> maxCharsText <> " characters total (including the leading emoji). Keep it short!"
        , ""
        , "Example output (exactly 1 line):"
        , "🤔 Ever trusted a machine more than your gut?"
        , ""
        , "Another example:"
        , "📖 Best book from childhood still worth rereading?"
        ]
      user = T.intercalate "\n"
        [ "Generate a discussion question for this page (max " <> maxCharsText <> " characters):"
        , ""
        , "Title: " <> rdTitle rd
        , "URL: " <> rdUrl rd
        , "Date: " <> rdDate rd
        , ""
        , "Content:"
        , rdBody rd
        ]
  in PromptPair { ppSystem = system, ppUser = user }

parseQuestionAndTags :: Text -> (Text, Text)
parseQuestionAndTags modelOutput =
  let nonEmptyLines = filter (not . T.null . T.strip) (T.splitOn "\n" (T.strip modelOutput))
  in case nonEmptyLines of
    (q : t : _) -> (T.strip q, T.strip t)
    [q]         -> (T.strip q, "")
    []          -> ("", "")

assemblePost :: Text -> ReflectionData -> Text
assemblePost modelOutput rd =
  let (question, tags) = parseQuestionAndTags modelOutput
      titlePart = [rdTitle rd, ""]
      questionPart = case T.null question of
        True  -> []
        False -> [aiQuestionPrefix <> question, ""]
      tagsPart = case T.null tags of
        True  -> []
        False -> [tags]
      urlPart = [rdUrl rd]
  in T.intercalate "\n" (titlePart <> questionPart <> tagsPart <> urlPart)

buildShortenQuestionPrompt :: Text -> Int -> PromptPair
buildShortenQuestionPrompt question overage =
  let currentLength = T.length question
      targetLength = currentLength - overage
      system = T.intercalate "\n"
        [ "You shorten social media discussion questions. Return ONLY the shortened question — nothing else."
        , "Keep the same meaning, tone, and emoji prefix. The question MUST end with a question mark."
        , "Remove unnecessary words. Think Strunk and White for concision."
        ]
      user = T.intercalate "\n"
        [ "Shorten this question by at least " <> T.pack (show overage) <> " characters. Current length: " <> T.pack (show currentLength) <> " characters. Target: at most " <> T.pack (show targetLength) <> " characters."
        , ""
        , "Question: " <> question
        ]
  in PromptPair { ppSystem = system, ppUser = user }
