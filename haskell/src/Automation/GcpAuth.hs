{-# LANGUAGE OverloadedStrings #-}

module Automation.GcpAuth
  ( ServiceAccountKey (..)
  , JwtClaims (..)
  , TokenResponse (..)
  , parseServiceAccountKey
  , parseRSAPrivateKey
  , createJwt
  , getAccessToken
  , getAccessTokenWithScope
  , cloudPlatformScope
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
import Crypto.PubKey.RSA (PrivateKey (..))
import qualified Crypto.PubKey.RSA as RSA
import Crypto.PubKey.RSA.PKCS15 (sign)
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Base64.URL as B64URL
import qualified Data.ByteString.Char8 as C8
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word8)
import Network.HTTP.Client
  ( Manager
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
parseRSAPrivateKey pemText = do
  derBytes <- decodePem pemText
  parseDerPrivateKey derBytes

decodePem :: Text -> Either Text ByteString
decodePem pemText =
  let textLines = T.lines pemText
      bodyLines = filter (\l -> not (T.isPrefixOf "-----" l) && not (T.null (T.strip l))) textLines
      body = TE.encodeUtf8 (T.concat bodyLines)
  in case B64.decode body of
    Left err -> Left $ "PEM base64 decode error: " <> T.pack err
    Right bs -> Right bs

parseDerPrivateKey :: ByteString -> Either Text PrivateKey
parseDerPrivateKey derBytes =
  case parsePkcs8Key derBytes of
    Right key -> Right key
    Left _ -> case parsePkcs1Key derBytes of
      Right key -> Right key
      Left err -> Left $ "Failed to parse private key (tried PKCS#8 and PKCS#1): " <> err

parsePkcs8Key :: ByteString -> Either Text PrivateKey
parsePkcs8Key derBytes = do
  (sequenceContent, _) <- parseDerTag 0x30 derBytes
  (_version, afterVersion) <- parseDerTag 0x02 sequenceContent
  (_algorithmSeq, afterAlgorithm) <- parseDerTag 0x30 afterVersion
  (octetContent, _) <- parseDerTag 0x04 afterAlgorithm
  parsePkcs1Key octetContent

parsePkcs1Key :: ByteString -> Either Text PrivateKey
parsePkcs1Key derBytes = do
  (sequenceContent, _) <- parseDerTag 0x30 derBytes
  (_version, rest0) <- parseDerInteger sequenceContent
  (modulus, rest1) <- parseDerInteger rest0
  (publicExponent, rest2) <- parseDerInteger rest1
  (privateExponent, rest3) <- parseDerInteger rest2
  (prime1, rest4) <- parseDerInteger rest3
  (prime2, rest5) <- parseDerInteger rest4
  (exponent1, rest6) <- parseDerInteger rest5
  (exponent2, rest7) <- parseDerInteger rest6
  (coefficient, _) <- parseDerInteger rest7
  let publicKey = RSA.PublicKey
        { RSA.public_size = (integerBitLength modulus + 7) `div` 8
        , RSA.public_n = modulus
        , RSA.public_e = publicExponent
        }
  Right PrivateKey
    { private_pub = publicKey
    , private_d = privateExponent
    , private_p = prime1
    , private_q = prime2
    , private_dP = exponent1
    , private_dQ = exponent2
    , private_qinv = coefficient
    }

integerBitLength :: Integer -> Int
integerBitLength n
  | n <= 0 = 0
  | otherwise = go n 0
  where
    go 0 acc = acc
    go x acc = go (x `div` 2) (acc + 1)

parseDerTag :: Word8 -> ByteString -> Either Text (ByteString, ByteString)
parseDerTag expectedTag bs
  | BS.null bs = Left "Unexpected end of DER data"
  | BS.index bs 0 /= expectedTag =
      Left $ "Expected DER tag 0x" <> T.pack (showHexByte expectedTag)
          <> " but got 0x" <> T.pack (showHexByte (BS.index bs 0))
  | otherwise = do
      (contentLength, headerLength) <- parseDerLength (BS.drop 1 bs)
      let content = BS.take contentLength (BS.drop headerLength (BS.drop 1 bs))
          remaining = BS.drop (1 + headerLength + contentLength) bs
      Right (content, remaining)

parseDerInteger :: ByteString -> Either Text (Integer, ByteString)
parseDerInteger bs = do
  (content, remaining) <- parseDerTag 0x02 bs
  Right (bytesToInteger content, remaining)

parseDerLength :: ByteString -> Either Text (Int, Int)
parseDerLength bs
  | BS.null bs = Left "Unexpected end of DER length"
  | otherwise =
      let firstByte = BS.index bs 0
      in if firstByte < 0x80
        then Right (fromIntegral firstByte, 1)
        else
          let numLengthBytes = fromIntegral (firstByte - 0x80)
          in if BS.length bs < numLengthBytes + 1
            then Left "DER length extends beyond data"
            else
              let lengthBytes = BS.take numLengthBytes (BS.drop 1 bs)
                  lengthValue = BS.foldl' (\acc byte -> acc `shiftL` 8 .|. fromIntegral byte) 0 lengthBytes
              in Right (lengthValue, numLengthBytes + 1)

bytesToInteger :: ByteString -> Integer
bytesToInteger bs
  | BS.null bs = 0
  | BS.index bs 0 >= 0x80 =
      let unsigned = BS.foldl' (\acc byte -> acc `shiftL` 8 .|. fromIntegral byte) 0 bs :: Integer
          bitCount = BS.length bs * 8
      in unsigned - (1 `shiftL` bitCount)
  | otherwise = BS.foldl' (\acc byte -> acc `shiftL` 8 .|. fromIntegral byte) 0 bs

showHexByte :: Word8 -> String
showHexByte byte =
  let hi = byte `div` 16
      lo = byte `mod` 16
      hexChar n
        | n < 10 = toEnum (fromIntegral n + fromEnum '0')
        | otherwise = toEnum (fromIntegral n - 10 + fromEnum 'a')
  in [hexChar hi, hexChar lo]

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
getAccessToken = getAccessTokenWithScope cloudPlatformScope

getAccessTokenWithScope :: Text -> Manager -> ServiceAccountKey -> IO (Either Text Text)
getAccessTokenWithScope scope manager sak = do
  now <- round <$> getPOSIXTime :: IO Int
  case parseRSAPrivateKey (sakPrivateKey sak) of
    Left err -> pure $ Left err
    Right privKey -> do
      let claims = JwtClaims
            { jcIss   = sakClientEmail sak
            , jcScope = scope
            , jcAud   = T.pack tokenEndpoint
            , jcIat   = now
            , jcExp   = now + jwtExpirationSeconds
            }
      case createJwt claims privKey of
        Left err -> pure $ Left err
        Right jwt -> do
          initialRequest <- parseRequest tokenEndpoint
          let httpReq = urlEncodedBody
                [ ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
                , ("assertion", jwt)
                ] initialRequest
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
