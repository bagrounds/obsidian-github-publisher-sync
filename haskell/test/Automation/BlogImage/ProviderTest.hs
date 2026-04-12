module Automation.BlogImage.ProviderTest (tests) where

import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import qualified Automation.Gemini as Gemini
import Automation.BlogImage.Provider
import Automation.Secret (Secret (..))

tests :: TestTree
tests = testGroup "BlogImage.Provider"
  [ testGroup "ImageProvider"
      [ testCase "providerName returns cloudflare" $
          providerName (Cloudflare "acct") @?= "cloudflare"
      , testCase "providerName returns huggingface" $
          providerName HuggingFace @?= "huggingface"
      , testCase "providerName returns together" $
          providerName Together @?= "together"
      , testCase "providerName returns pollinations" $
          providerName Pollinations @?= "pollinations"
      , testCase "providerName returns gemini" $
          providerName GeminiImage @?= "gemini"
      , testCase "Cloudflare carries account ID" $
          case Cloudflare "my-account-123" of
            Cloudflare accountId -> accountId @?= "my-account-123"
      , testCase "Eq distinguishes constructors" $
          assertBool "different providers are not equal" $ HuggingFace /= Together
      , testCase "Show includes constructor name" $
          assertBool "show contains HuggingFace" $ "HuggingFace" `isInfixOf` show HuggingFace
      ]
  , testGroup "PromptDescriber"
      [ testCase "Show redacts API key" $
          let describer = PromptDescriber (Secret "super-secret") Gemini.Gemini25Flash
          in assertBool "show should not contain secret" $
               not ("super-secret" `isInfixOf` show describer)
      , testCase "Eq compares by value" $
          let describer1 = PromptDescriber (Secret "key1") Gemini.Gemini25Flash
              describer2 = PromptDescriber (Secret "key1") Gemini.Gemini25Flash
          in describer1 @?= describer2
      , testCase "Eq distinguishes different models" $
          let describer1 = PromptDescriber (Secret "key") Gemini.Gemini25Flash
              describer2 = PromptDescriber (Secret "key") Gemini.Gemini20Flash
          in assertBool "different models should not be equal" $ describer1 /= describer2
      ]
  , testGroup "ImageProviderConfig"
      [ testCase "Show is derivable and works" $
          let config = ImageProviderConfig HuggingFace (Secret "key") "model" Nothing
          in assertBool "show contains HuggingFace" $ "HuggingFace" `isInfixOf` show config
      , testCase "Show redacts API key" $
          let config = ImageProviderConfig Together (Secret "secret-key") "model" Nothing
          in assertBool "show should not contain secret" $
               not ("secret-key" `isInfixOf` show config)
      , testCase "Eq compares by value" $
          let config = ImageProviderConfig Pollinations (Secret "") "flux" Nothing
          in config @?= config
      ]
  , testGroup "mimeTypeToExtension"
      [ testCase "jpeg returns .jpg" $
          mimeTypeToExtension "image/jpeg" @?= ".jpg"
      , testCase "png returns .png" $
          mimeTypeToExtension "image/png" @?= ".png"
      , testCase "webp returns .webp" $
          mimeTypeToExtension "image/webp" @?= ".webp"
      , testCase "gif returns .gif" $
          mimeTypeToExtension "image/gif" @?= ".gif"
      , testCase "unknown returns .jpg" $
          mimeTypeToExtension "application/octet-stream" @?= ".jpg"
      , testCase "handles charset suffix" $
          mimeTypeToExtension "image/png; charset=utf-8" @?= ".png"
      ]
  , testGroup "error classification"
      [ testCase "isQuotaError detects 429" $
          isQuotaError "HTTP 429 Too Many Requests" @?= True
      , testCase "isQuotaError detects RESOURCE_EXHAUSTED" $
          isQuotaError "RESOURCE_EXHAUSTED: quota limit" @?= True
      , testCase "isQuotaError returns False for other errors" $
          isQuotaError "Internal Server Error" @?= False
      , testCase "isDailyQuotaError detects daily quota" $
          isDailyQuotaError "quota limit daily exceeded" @?= True
      , testCase "isDailyQuotaError returns False for non-daily quota" $
          isDailyQuotaError "quota exceeded" @?= False
      , testCase "isProviderUnavailableError detects 410" $
          isProviderUnavailableError "HTTP 410 Gone" @?= True
      , testCase "isProviderUnavailableError detects deprecated" $
          isProviderUnavailableError "model deprecated" @?= True
      ]
  , testGroup "resolveImageProviders"
      [ testCase "returns empty for empty env" $
          assertBool "should be empty" $ null (resolveImageProviders Map.empty)
      , testCase "creates Gemini provider when key present" $
          let env = Map.fromList [("GEMINI_API_KEY", "test-key")]
              providers = resolveImageProviders env
          in do
            assertBool "should have at least one provider" $ not (null providers)
            case providers of
              (first:_) -> providerName (ipcProvider first) @?= "gemini"
              []        -> assertBool "should have provider" False
      , testCase "creates providers in correct order" $
          let env = Map.fromList
                [ ("CLOUDFLARE_API_TOKEN", "cf-token")
                , ("CLOUDFLARE_ACCOUNT_ID", "cf-account")
                , ("HUGGINGFACE_API_TOKEN", "hf-token")
                , ("TOGETHER_API_TOKEN", "together-key")
                , ("POLLINATIONS_ENABLED", "true")
                , ("GEMINI_API_KEY", "gemini-key")
                ]
              providers = resolveImageProviders env
              names = fmap (providerName . ipcProvider) providers
          in names @?= ["cloudflare", "huggingface", "together", "pollinations", "gemini"]
      , testCase "configs with Gemini key have describer" $
          let env = Map.fromList
                [ ("GEMINI_API_KEY", "gemini-key")
                , ("HUGGINGFACE_API_TOKEN", "hf-key")
                ]
              providers = resolveImageProviders env
              huggingFaceProviders = filter (\p -> ipcProvider p == HuggingFace) providers
          in case huggingFaceProviders of
            [p] -> assertBool "should have describer" $ isJust (ipcDescriber p)
            _   -> assertBool "expected one HuggingFace provider" False
      , testCase "configs without Gemini key have no describer" $
          let env = Map.fromList [("HUGGINGFACE_API_TOKEN", "hf-key")]
              providers = resolveImageProviders env
          in case providers of
            [p] -> ipcDescriber p @?= Nothing
            _   -> assertBool "expected one provider" False
      ]
  , testGroup "properties"
      [ testProperty "mimeTypeToExtension always starts with dot" $
          \s -> T.isPrefixOf "." (mimeTypeToExtension (T.pack s))
      ]
  ]
