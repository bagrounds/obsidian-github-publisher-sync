module Automation.BlogImageTest (tests) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import Test.QuickCheck (Property, (==>), forAll, listOf1, elements)

import Automation.BlogImage

tests :: TestTree
tests = testGroup "BlogImage"
  [ testGroup "hasEmbeddedImage"
      [ testCase "detects Obsidian image embed" $
          hasEmbeddedImage "some text\n![[attachments/photo.jpg]]\nmore" @?= True
      , testCase "detects Obsidian embed without attachments prefix" $
          hasEmbeddedImage "![[my-image.png]]" @?= True
      , testCase "detects markdown image embed" $
          hasEmbeddedImage "![alt text](images/photo.webp)" @?= True
      , testCase "returns False for plain text" $
          hasEmbeddedImage "no images here" @?= False
      , testCase "returns False for non-image embed" $
          hasEmbeddedImage "![[some-note]]" @?= False
      , testCase "detects gif extension" $
          hasEmbeddedImage "![[attachments/anim.gif]]" @?= True
      ]
  , testGroup "shouldRegenerateImage"
      [ testCase "returns True when regenerate_image is true" $
          shouldRegenerateImage "---\nregenerate_image: true\n---\nbody" @?= True
      , testCase "returns False when field is absent" $
          shouldRegenerateImage "---\ntitle: hello\n---\nbody" @?= False
      , testCase "returns False for no frontmatter" $
          shouldRegenerateImage "just body text" @?= False
      , testCase "returns True for quoted true" $
          shouldRegenerateImage "---\nregenerate_image: \"true\"\n---\nbody" @?= True
      ]
  , testGroup "insertImageEmbed"
      [ testCase "inserts after H1" $
          insertImageEmbed "# Title\nbody text" "photo.jpg"
            @?= "# Title\n![[attachments/photo.jpg]]\nbody text"
      , testCase "returns unchanged if no H1" $
          insertImageEmbed "no heading\nbody" "photo.jpg"
            @?= "no heading\nbody"
      , testCase "handles frontmatter before H1" $
          insertImageEmbed "---\ntitle: test\n---\n# Title\nbody" "img.png"
            @?= "---\ntitle: test\n---\n# Title\n![[attachments/img.png]]\nbody"
      ]
  , testGroup "extractTitle"
      [ testCase "extracts from frontmatter" $
          extractTitle "---\ntitle: My Post\n---\nbody" @?= "My Post"
      , testCase "extracts from H1" $
          extractTitle "# Hello World\nbody" @?= "Hello World"
      , testCase "prefers frontmatter over H1" $
          extractTitle "---\ntitle: FM Title\n---\n# H1 Title\nbody" @?= "FM Title"
      , testCase "returns empty for no title" $
          extractTitle "just some text" @?= ""
      , testCase "strips quotes from frontmatter title" $
          extractTitle "---\ntitle: \"Quoted Title\"\n---\n" @?= "Quoted Title"
      ]
  , testGroup "sanitizeForYaml"
      [ testCase "replaces newlines with spaces" $
          sanitizeForYaml "line1\nline2" @?= "line1 line2"
      , testCase "removes quotes and backslashes" $
          sanitizeForYaml "it's a \"test\" with \\slash" @?= "its a test with slash"
      , testCase "collapses whitespace" $
          sanitizeForYaml "too   many   spaces" @?= "too many spaces"
      , testCase "trims" $
          sanitizeForYaml "  padded  " @?= "padded"
      ]
  , testGroup "isPostFile"
      [ testCase "accepts dated markdown file" $
          isPostFile "2024-01-15-my-post.md" @?= True
      , testCase "rejects index.md" $
          isPostFile "index.md" @?= False
      , testCase "rejects AGENTS.md" $
          isPostFile "AGENTS.md" @?= False
      , testCase "rejects non-dated file" $
          isPostFile "my-post.md" @?= False
      , testCase "rejects non-markdown" $
          isPostFile "2024-01-15-photo.jpg" @?= False
      ]
  , testGroup "mimeTypeToExtension"
      [ testCase "jpeg -> .jpg" $
          mimeTypeToExtension "image/jpeg" @?= ".jpg"
      , testCase "png -> .png" $
          mimeTypeToExtension "image/png" @?= ".png"
      , testCase "webp -> .webp" $
          mimeTypeToExtension "image/webp" @?= ".webp"
      , testCase "unknown -> .jpg" $
          mimeTypeToExtension "application/octet-stream" @?= ".jpg"
      , testCase "handles charset suffix" $
          mimeTypeToExtension "image/png; charset=utf-8" @?= ".png"
      ]
  , testGroup "notePathToImageBaseName"
      [ testCase "combines dir and stem" $
          notePathToImageBaseName "/repo/ai-blog/2024-01-15-my-post.md"
            @?= "ai-blog-2024-01-15-my-post"
      , testCase "lowercases and sanitizes" $
          notePathToImageBaseName "/repo/My Blog/Post Title.md"
            @?= "my-blog-post-title"
      ]
  , testGroup "isQuotaError"
      [ testCase "detects 429" $
          isQuotaError "HTTP 429 Too Many Requests" @?= True
      , testCase "detects RESOURCE_EXHAUSTED" $
          isQuotaError "RESOURCE_EXHAUSTED: quota limit" @?= True
      , testCase "detects quota keyword" $
          isQuotaError "quota exceeded" @?= True
      , testCase "returns False for other errors" $
          isQuotaError "Internal Server Error" @?= False
      ]
  , testGroup "isDailyQuotaError"
      [ testCase "detects daily quota" $
          isDailyQuotaError "quota limit daily exceeded" @?= True
      , testCase "detects PerDay quota" $
          isDailyQuotaError "quota PerDay limit" @?= True
      , testCase "non-daily quota is False" $
          isDailyQuotaError "quota exceeded" @?= False
      ]
  , testGroup "isProviderUnavailableError"
      [ testCase "detects 410" $
          isProviderUnavailableError "HTTP 410 Gone" @?= True
      , testCase "detects 401" $
          isProviderUnavailableError "HTTP 401 Unauthorized" @?= True
      , testCase "detects deprecated" $
          isProviderUnavailableError "model deprecated" @?= True
      ]
  , testGroup "cleanContentForPrompt"
      [ testCase "strips frontmatter" $
          assertBool "should not contain frontmatter delimiters" $
            not (T.isInfixOf "---" (cleanContentForPrompt "---\ntitle: test\n---\n# Hello\nbody"))
      , testCase "strips markdown headings" $
          assertBool "should not contain heading markers" $
            not (T.isPrefixOf "# " (cleanContentForPrompt "# Hello World"))
      ]
  , testGroup "buildImagePrompt"
      [ testCase "starts with instruction prefix" $
          assertBool "should start with generate prefix" $
            T.isPrefixOf "generate an image" (buildImagePrompt "# My Post\nSome content here")
      , testCase "respects max length" $
          assertBool "should not exceed 2048 chars" $
            T.length (buildImagePrompt (T.replicate 5000 "word ")) <= 2048
      ]
  , testGroup "updateFrontmatterFields"
      [ testCase "updates existing field" $
          updateFrontmatterFields "---\ntitle: old\n---\nbody"
            [("title", "new")]
            @?= "---\ntitle: new\n---\nbody"
      , testCase "adds new field" $
          let result = updateFrontmatterFields "---\ntitle: test\n---\nbody"
                [("image_date", "2024-01-15")]
          in assertBool "should contain new field" $
               T.isInfixOf "image_date:" result
      , testCase "preserves body" $
          assertBool "should preserve body" $
            T.isInfixOf "body content" $
              updateFrontmatterFields "---\ntitle: test\n---\nbody content"
                [("new_field", "value")]
      ]
  , testGroup "removeImageEmbed"
      [ testCase "removes Obsidian embed and returns name" $
          let (content, mName) = removeImageEmbed "before\n![[attachments/photo.jpg]]\nafter"
          in do
            assertBool "should remove embed" $ not (T.isInfixOf "![[" content)
            mName @?= Just "photo.jpg"
      , testCase "returns Nothing when no embed" $
          let (_, mName) = removeImageEmbed "no images here"
          in mName @?= Nothing
      ]
  , testGroup "resolveImageProviders"
      [ testCase "returns empty for empty env" $
          assertBool "should be empty" $ null (resolveImageProviders Map.empty)
      , testCase "creates Gemini provider when key present" $
          let env = Map.fromList [("GEMINI_API_KEY", "test-key")]
              providers = resolveImageProviders env
          in do
            assertBool "should have at least one provider" $ not (null providers)
            ipcName (Prelude.head providers) @?= "gemini"
      , testCase "creates Cloudflare provider when token and account present" $
          let env = Map.fromList
                [ ("CLOUDFLARE_API_TOKEN", "cf-token")
                , ("CLOUDFLARE_ACCOUNT_ID", "cf-account")
                ]
              providers = resolveImageProviders env
          in do
            assertBool "should have provider" $ not (null providers)
            ipcName (Prelude.head providers) @?= "cloudflare"
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
              names = fmap ipcName providers
          in names @?= ["cloudflare", "huggingface", "together", "pollinations", "gemini"]
      , testCase "skips Pollinations when not enabled" $
          let env = Map.fromList [("POLLINATIONS_ENABLED", "false")]
              providers = resolveImageProviders env
          in assertBool "should be empty" $ null providers
      , testCase "uses default models" $
          let env = Map.fromList [("GEMINI_API_KEY", "key")]
              providers = resolveImageProviders env
          in case providers of
            [p] -> ipcModel p @?= "gemini-3.1-flash-image-preview"
            _   -> assertBool "expected exactly one provider" False
      , testCase "uses custom model from env" $
          let env = Map.fromList
                [ ("GEMINI_API_KEY", "key")
                , ("IMAGE_GEMINI_MODEL", "custom-model")
                ]
              providers = resolveImageProviders env
          in case providers of
            [p] -> ipcModel p @?= "custom-model"
            _   -> assertBool "expected exactly one provider" False
      ]
  , testGroup "properties"
      [ testProperty "buildImagePrompt never exceeds max length" $
          \content -> T.length (buildImagePrompt (T.pack content)) <= 2048
      , testProperty "sanitizeForYaml removes quotes" $
          \s -> let sanitized = sanitizeForYaml (T.pack s)
                in not (T.any (\c -> c == '"' || c == '\'' || c == '\\' || c == '`') sanitized)
      , testProperty "mimeTypeToExtension always starts with dot" $
          \s -> T.isPrefixOf "." (mimeTypeToExtension (T.pack s))
      , testProperty "hasEmbeddedImage returns False for alphanumeric text" $
          forAll (fmap T.pack $ listOf1 $ elements (['a'..'z'] <> ['0'..'9'] <> [' ', '\n'])) $
            \t -> not (hasEmbeddedImage t)
      , testProperty "insertImageEmbed is idempotent on content without H1" $
          \s -> let t = T.pack s
                    noH1 = not (T.isInfixOf "\n# " t) && not (T.isPrefixOf "# " t)
                in noH1 ==> insertImageEmbed t "test.jpg" == t
      ]
  ]
