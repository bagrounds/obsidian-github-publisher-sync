module Automation.BlogImage.ContentDirectory
  ( ContentDirectory (..)
  , contentDirectoryToText
  , contentDirectoryFromText
  ) where

import Data.Text (Text)

data ContentDirectory
  = Reflections
  | AiBlog
  | AutoBlogZero
  | ChickieLoo
  | SystemsForPublicGood
  | Articles
  | Books
  | BotChats
  | Games
  | Products
  | Software
  | Tools
  | Topics
  deriving (Show, Eq, Ord, Bounded, Enum)

contentDirectoryToText :: ContentDirectory -> Text
contentDirectoryToText = \case
  Reflections          -> "reflections"
  AiBlog               -> "ai-blog"
  AutoBlogZero         -> "auto-blog-zero"
  ChickieLoo           -> "chickie-loo"
  SystemsForPublicGood -> "systems-for-public-good"
  Articles             -> "articles"
  Books                -> "books"
  BotChats             -> "bot-chats"
  Games                -> "games"
  Products             -> "products"
  Software             -> "software"
  Tools                -> "tools"
  Topics               -> "topics"

contentDirectoryFromText :: Text -> Maybe ContentDirectory
contentDirectoryFromText = \case
  "reflections"            -> Just Reflections
  "ai-blog"               -> Just AiBlog
  "auto-blog-zero"        -> Just AutoBlogZero
  "chickie-loo"           -> Just ChickieLoo
  "systems-for-public-good" -> Just SystemsForPublicGood
  "articles"              -> Just Articles
  "books"                 -> Just Books
  "bot-chats"             -> Just BotChats
  "games"                 -> Just Games
  "products"              -> Just Products
  "software"              -> Just Software
  "tools"                 -> Just Tools
  "topics"                -> Just Topics
  _                       -> Nothing
