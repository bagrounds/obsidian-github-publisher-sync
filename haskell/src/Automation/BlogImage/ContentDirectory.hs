module Automation.BlogImage.ContentDirectory
  ( ContentDirectory (..)
  , contentDirectoryToText
  , contentDirectoryFromText
  , knownDirectories
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
  | AutoBlogSeries Text
  deriving (Show, Eq, Ord)

knownDirectories :: [ContentDirectory]
knownDirectories =
  [ Reflections, AiBlog, AutoBlogZero, ChickieLoo, SystemsForPublicGood
  , Articles, Books, BotChats, Games, Products, Software, Tools, Topics
  ]

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
  AutoBlogSeries name  -> name

contentDirectoryFromText :: Text -> ContentDirectory
contentDirectoryFromText = \case
  "reflections"            -> Reflections
  "ai-blog"               -> AiBlog
  "auto-blog-zero"        -> AutoBlogZero
  "chickie-loo"           -> ChickieLoo
  "systems-for-public-good" -> SystemsForPublicGood
  "articles"              -> Articles
  "books"                 -> Books
  "bot-chats"             -> BotChats
  "games"                 -> Games
  "products"              -> Products
  "software"              -> Software
  "tools"                 -> Tools
  "topics"                -> Topics
  name                    -> AutoBlogSeries name
