{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.GcpAuth
  ( ServiceAccountKey (..)
  , JwtClaims (..)
  , TokenResponse (..)
  , parseServiceAccountKey
  , createJwt
  , getAccessToken
  ) where

import Automation.Json
  ( FromValue (..)
  , (.=)
  , (.:)
  , encode
  , eitherDecodeStrict
  , object
  , withObject
  )
import qualified Automation.Json as Json
import Crypto.Hash (SHA256 (..))
import Crypto.PubKey.RSA (PrivateKey)
import Crypto.PubKey.RSA.PKCS15 (sign)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Base64.URL as B64URL
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseStatus
  , urlEncodedBody
  )
import Network.HTTP.Types.Status (statusCode)

data ServiceAccountKey = ServiceAccountKey
  { sakProjectId   :: Text
  , sakClientEmail :: Text
  , sakPrivateKey  :: Text
  } deriving (Show, Eq)

instance FromValue ServiceAccountKey where
  fromValue = withObject "ServiceAccountKey" $ \v ->
    ServiceAccountKey
      <$> v .: "project_id"
      <*> v .: "client_email"
      <*> v .: "private_key"

data JwtClaims = JwtClaims
  { jcIss   :: Text
  , jcScope :: Text
  , jcAud   :: Text
  , jcIat   :: Int
  , jcExp   :: Int
  } deriving (Show, Eq)

data TokenResponse = TokenResponse
  { trAccessToken :: Text
  , trTokenType   :: Text
  , trExpiresIn   :: Int
  } deriving (Show, Eq)

instance FromValue TokenResponse where
  fromValue = withObject "TokenResponse" $ \v ->
    TokenResponse
      <$> v .: "access_token"
      <*> v .: "token_type"
      <*> v .: "expires_in"

tokenEndpoint :: String
tokenEndpoint = "https://oauth2.googleapis.com/token"

jwtExpirationSeconds :: Int
jwtExpirationSeconds = 3600

cloudPlatformScope :: Text
cloudPlatformScope = "https://www.googleapis.com/auth/cloud-platform"

base64UrlEncode :: ByteString -> ByteString
base64UrlEncode = C8.filter (/= '=') . B64URL.encode

parseServiceAccountKey :: Text -> Either Text ServiceAccountKey
parseServiceAccountKey raw =
  let rawBs = TE.encodeUtf8 raw
      decoded = case eitherDecodeStrict rawBs of
        Right key -> Right key
        Left _ ->
          case B64.decode rawBs of
            Right decodedBs -> case eitherDecodeStrict decodedBs of
              Right key -> Right key
              Left err  -> Left $ "Failed to parse decoded base64 JSON: " <> T.pack err
            Left err -> Left $ "Failed to parse JSON or base64: " <> T.pack (show err)
  in case decoded of
    Left err -> Left err
    Right key
      | T.null (sakProjectId key)   -> Left "Service account key must contain project_id"
      | T.null (sakClientEmail key) -> Left "Service account key must contain client_email"
      | T.null (sakPrivateKey key)  -> Left "Service account key must contain private_key"
      | otherwise                   -> Right key

parseRSAPrivateKey :: Text -> Either Text PrivateKey
parseRSAPrivateKey _ = Left "RSA private key parsing not yet implemented"

encodeJwtPayload :: JwtClaims -> ByteString
encodeJwtPayload claims =
  let payload = object
        [ "iss"   .= jcIss claims
        , "scope" .= jcScope claims
        , "aud"   .= jcAud claims
        , "iat"   .= jcIat claims
        , "exp"   .= jcExp claims
        ]
  in LBS.toStrict $ encode payload

createJwt :: JwtClaims -> PrivateKey -> Either Text ByteString
createJwt claims privateKey =
  let header = base64UrlEncode $ LBS.toStrict $ encode $
        object ["alg" .= ("RS256" :: Text), "typ" .= ("JWT" :: Text)]
      payload = base64UrlEncode $ encodeJwtPayload claims
      signingInput = header <> "." <> payload
  in case sign Nothing (Just SHA256) privateKey signingInput of
    Left err  -> Left $ "RSA signing error: " <> T.pack (show err)
    Right sig -> Right $ signingInput <> "." <> base64UrlEncode sig

getAccessToken :: Manager -> ServiceAccountKey -> IO (Either Text Text)
getAccessToken manager sak = do
  now <- round <$> getPOSIXTime :: IO Int
  case parseRSAPrivateKey (sakPrivateKey sak) of
    Left err -> pure $ Left err
    Right privKey -> do
      let claims = JwtClaims
            { jcIss   = sakClientEmail sak
            , jcScope = cloudPlatformScope
            , jcAud   = T.pack tokenEndpoint
            , jcIat   = now
            , jcExp   = now + jwtExpirationSeconds
            }
      case createJwt claims privKey of
        Left err -> pure $ Left err
        Right jwt -> do
          initReq <- parseRequest tokenEndpoint
          let httpReq = urlEncodedBody
                [ ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
                , ("assertion", jwt)
                ] initReq
          response <- httpLbs httpReq manager
          let status = statusCode $ responseStatus response
          case status of
            200 ->
              case Json.eitherDecode (responseBody response) of
                Left err -> pure $ Left $ "Token response parse error: " <> T.pack err
                Right tokenResp -> pure $ Right $ trAccessToken tokenResp
            code -> pure $ Left $
              "Token endpoint returned status " <> T.pack (show code)
                <> ": " <> TE.decodeUtf8 (LBS.toStrict $ responseBody response)
