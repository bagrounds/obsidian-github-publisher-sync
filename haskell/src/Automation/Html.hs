{-# LANGUAGE OverloadedStrings #-}

module Automation.Html
  ( escapeHtml
  , textToHtml
  , formatDisplayDate
  , monthNames
  ) where

import Data.Text (Text)
import qualified Data.Text as T

monthNames :: [Text]
monthNames =
  [ "January", "February", "March", "April", "May", "June"
  , "July", "August", "September", "October", "November", "December"
  ]

escapeHtml :: Text -> Text
escapeHtml = T.concatMap escapeChar
  where
    escapeChar :: Char -> Text
    escapeChar '&'  = "&amp;"
    escapeChar '<'  = "&lt;"
    escapeChar '>'  = "&gt;"
    escapeChar '"'  = "&quot;"
    escapeChar '\'' = "&#39;"
    escapeChar c    = T.singleton c

textToHtml :: Text -> Text
textToHtml = T.replace "\n" "<br>" . escapeHtml

formatDisplayDate :: Text -> Text
formatDisplayDate date =
  case T.splitOn "-" date of
    [yearT, monthT, dayT] ->
      let year  = yearT
          month = readMonth monthT
          day   = T.dropWhile (== '0') dayT
      in month <> " " <> (if T.null day then "0" else day) <> ", " <> year
    _ -> date

readMonth :: Text -> Text
readMonth t =
  case reads (T.unpack t) :: [(Int, String)] of
    [(n, "")] | n >= 1 && n <= 12 -> monthNames !! (n - 1)
    _                              -> "Unknown"
