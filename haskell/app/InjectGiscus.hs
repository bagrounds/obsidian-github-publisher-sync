module Main where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (getArgs, lookupEnv)
import System.IO (hSetBuffering, stdout, BufferMode(..))

import Automation.StaticGiscus
  ( fetchAllDiscussions
  , buildCommentsMap
  , processHtmlFiles
  )

owner :: Text
owner = "bagrounds"

repo :: Text
repo = "obsidian-github-publisher-sync"

categoryId :: Text
categoryId = "DIC_kwDOLuWiLM4Ckd0H"

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  mToken <- lookupEnv "GITHUB_TOKEN"
  case mToken of
    Nothing -> TIO.putStrLn "{\"event\":\"skip_static_giscus\",\"reason\":\"no GITHUB_TOKEN\"}"
    Just token -> do
      TIO.putStrLn "{\"event\":\"static_giscus_start\"}"

      manager <- newManager tlsManagerSettings
      discussions <- fetchAllDiscussions manager (T.pack token) owner repo categoryId
      TIO.putStrLn $ "{\"event\":\"static_giscus_fetched\",\"discussionCount\":" <> T.pack (show (length discussions)) <> "}"

      let commentsMap = buildCommentsMap discussions
          pathnames = length commentsMap
      TIO.putStrLn $ "{\"event\":\"static_giscus_mapped\",\"pathnames\":" <> T.pack (show pathnames) <> "}"

      args <- getArgs
      let publicDir = case args of
            (d:_) -> d
            []    -> "public"

      injectedFiles <- processHtmlFiles publicDir commentsMap
      TIO.putStrLn $ "{\"event\":\"static_giscus_done\",\"injectedPages\":" <> T.pack (show (length injectedFiles)) <> "}"
