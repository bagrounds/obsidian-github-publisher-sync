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
import Automation.Frontmatter (YamlValue (..))

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
            [("title", YamlText "new")]
            @?= "---\ntitle: \"new\"\n---\nbody"
      , testCase "adds new field" $
          let result = updateFrontmatterFields "---\ntitle: test\n---\nbody"
                [("image_date", YamlText "2024-01-15")]
          in assertBool "should contain new field" $
               T.isInfixOf "image_date:" result
      , testCase "preserves body" $
          assertBool "should preserve body" $
            T.isInfixOf "body content" $
              updateFrontmatterFields "---\ntitle: test\n---\nbody content"
                [("new_field", YamlText "value")]
      , testCase "replaces multi-line field without orphaning continuation lines" $
          let input = "---\naliases:\n  - \"old alias\"\ntitle: test\n---\nbody"
              result = updateFrontmatterFields input [("aliases", YamlText "new-value")]
          in do
            assertBool "should not have orphaned continuation line" $
              not (T.isInfixOf "  - \"old alias\"" result)
            assertBool "should have new value" $
              T.isInfixOf "aliases: \"new-value\"" result
            assertBool "should preserve title" $
              T.isInfixOf "title: test" result
      , testCase "boolean false renders as native YAML boolean" $
          let result = updateFrontmatterFields "---\nregenerate_image: true\n---\nbody"
                [("regenerate_image", YamlBool False)]
          in assertBool "should have unquoted false" $
               T.isInfixOf "regenerate_image: false" result
      , testCase "boolean true renders as native YAML boolean" $
          let result = updateFrontmatterFields "---\nshare: false\n---\nbody"
                [("share", YamlBool True)]
          in assertBool "should have unquoted true" $
               T.isInfixOf "share: true" result
      ]
  , testGroup "applyField"
      [ testCase "replaces scalar field" $
          applyField ["title: old", "tags:"] ("title", YamlText "new")
            @?= ["title: \"new\"", "tags:"]
      , testCase "adds missing field" $
          applyField ["title: test"] ("new_key", YamlText "value")
            @?= ["title: test", "new_key: \"value\""]
      , testCase "drops continuation lines when replacing multi-line field" $
          applyField ["aliases:", "  - \"first\"", "  - \"second\"", "title: test"] ("aliases", YamlText "replaced")
            @?= ["aliases: \"replaced\"", "title: test"]
      , testCase "boolean value renders unquoted" $
          applyField ["regenerate_image: true"] ("regenerate_image", YamlBool False)
            @?= ["regenerate_image: false"]
      , testCase "preserves unrelated arrays when adding new field" $
          applyField
            ["share: true", "aliases:", "  - \"My Title\"", "title: \"test\""]
            ("image_date", YamlText "2026-03-30")
            @?= ["share: true", "aliases:", "  - \"My Title\"", "title: \"test\"", "image_date: \"2026-03-30\""]
      , testCase "preserves unrelated arrays when updating different field" $
          applyField
            ["share: true", "aliases:", "  - \"My Title\"", "title: \"old\""]
            ("title", YamlText "new")
            @?= ["share: true", "aliases:", "  - \"My Title\"", "title: \"new\""]
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
  , testGroup "cleanContentForPrompt (extended)"
      [ testCase "strips code blocks" $
          let input = "---\ntitle: test\n---\nbefore\n```python\nprint('hello')\n```\nafter"
          in assertBool "should not contain code block content" $
               not (T.isInfixOf "print" (cleanContentForPrompt input))
      , testCase "strips Obsidian embeds" $
          assertBool "should not contain embed" $
            not (T.isInfixOf "![[" (cleanContentForPrompt "text\n![[attachments/photo.jpg]]\nmore"))
      , testCase "strips headings at all levels" $ do
          let cleaned = cleanContentForPrompt "# H1\n## H2\n### H3\nbody"
          assertBool "should not have # prefix" $ not (T.isInfixOf "# " cleaned)
      , testCase "strips ordered lists" $
          let input = "1. first item\n2. second item"
          in assertBool "should strip numbers" $
               not (T.isInfixOf "1." (cleanContentForPrompt input))
      , testCase "strips unordered lists" $
          let input = "- bullet one\n* bullet two"
              cleaned = cleanContentForPrompt input
          in do
            assertBool "should strip dash bullet" $ not (T.isPrefixOf "- " cleaned)
            assertBool "contains content" $ T.isInfixOf "bullet" cleaned
      , testCase "strips blockquotes" $
          let cleaned = cleanContentForPrompt "> quoted text"
          in assertBool "should not have >" $ not (T.isPrefixOf ">" (T.stripStart cleaned))
      , testCase "strips table cells" $
          let input = "| col1 | col2 |\n|---|---|\n| a | b |"
          in assertBool "should strip table separators" $
               not (T.isInfixOf "|---|" (cleanContentForPrompt input))
      , testCase "strips emphasis markers" $
          let cleaned = cleanContentForPrompt "some **bold** and *italic* text"
          in assertBool "no asterisks" $ not (T.any (== '*') cleaned)
      , testCase "strips inline code" $
          assertBool "should not contain backtick content" $
            not (T.isInfixOf "inline" (cleanContentForPrompt "text `inline code` more"))
      , testCase "strips markdown images" $
          assertBool "should not contain image syntax" $
            not (T.isInfixOf "![" (cleanContentForPrompt "![alt](path/to/image.png)"))
      , testCase "strips markdown links but keeps text" $
          let cleaned = cleanContentForPrompt "see [my link](http://example.com) here"
          in assertBool "should keep link text" $ T.isInfixOf "my link" cleaned
      ]
  , testGroup "buildImagePrompt (extended)"
      [ testCase "truncates at exactly max length" $
          let longContent = T.replicate 3000 "x"
              result = buildImagePrompt longContent
          in result @?= T.take 2048 result
      , testCase "does not truncate short content" $
          let result = buildImagePrompt "short post"
              cleaned = cleanContentForPrompt "short post"
          in assertBool "should contain full cleaned content" $
               T.isInfixOf cleaned result
      ]
  , testGroup "extractTitle (extended)"
      [ testCase "strips nested quotes" $
          extractTitle "---\ntitle: \"'inner'\"\n---\nbody" @?= "'inner'"
      , testCase "empty frontmatter falls back to H1" $
          extractTitle "---\n---\n# Fallback Title" @?= "Fallback Title"
      , testCase "title with single quotes" $
          extractTitle "---\ntitle: 'Single Quoted'\n---\n" @?= "Single Quoted"
      , testCase "frontmatter with no title and no H1" $
          extractTitle "---\ntags: foo\n---\njust body" @?= ""
      ]
  , testGroup "hasEmbeddedImage (extended)"
      [ testCase "detects jpg extension" $
          hasEmbeddedImage "![[photo.jpg]]" @?= True
      , testCase "detects jpeg extension" $
          hasEmbeddedImage "![[photo.jpeg]]" @?= True
      , testCase "detects png extension" $
          hasEmbeddedImage "![[photo.png]]" @?= True
      , testCase "detects gif extension (nested)" $
          hasEmbeddedImage "![[sub/dir/anim.gif]]" @?= True
      , testCase "detects webp extension" $
          hasEmbeddedImage "![[photo.webp]]" @?= True
      , testCase "path with subdirectories" $
          hasEmbeddedImage "![[deep/nested/path/image.png]]" @?= True
      , testCase "rejects non-image extension" $
          hasEmbeddedImage "![[document.pdf]]" @?= False
      ]
  , testGroup "notePathToImageBaseName (extended)"
      [ testCase "handles special characters" $
          notePathToImageBaseName "/repo/My (Cool) Blog/It's a Test!.md"
            @?= "my-cool-blog-it-s-a-test"
      , testCase "deeply nested path uses parent dir and stem" $
          notePathToImageBaseName "/a/b/c/d/my-dir/my-file.md"
            @?= "my-dir-my-file"
      , testCase "collapses multiple dashes" $
          notePathToImageBaseName "/repo/foo---bar/baz--qux.md"
            @?= "foo-bar-baz-qux"
      ]
  , testGroup "removeImageEmbed (extended)"
      [ testCase "removes embed without attachments prefix" $
          let (content, mName) = removeImageEmbed "before\n![[photo.jpg]]\nafter"
          in do
            assertBool "should remove embed" $ not (T.isInfixOf "![[" content)
            mName @?= Just "photo.jpg"
      , testCase "removes embed with attachments prefix" $
          let (_, mName) = removeImageEmbed "![[attachments/img.png]]\nrest"
          in mName @?= Just "img.png"
      , testCase "only removes first image embed" $
          let input = "![[a.jpg]]\ntext\n![[b.png]]"
              (content, mName) = removeImageEmbed input
          in do
            mName @?= Just "a.jpg"
            assertBool "second embed should remain" $ T.isInfixOf "![[b.png]]" content
      ]
  , testGroup "sanitizeForYaml (extended)"
      [ testCase "removes backticks" $
          sanitizeForYaml "some `code` text" @?= "some code text"
      , testCase "handles multiline input" $
          sanitizeForYaml "line1\nline2\nline3" @?= "line1 line2 line3"
      , testCase "strips leading and trailing whitespace" $
          sanitizeForYaml "   spaced   " @?= "spaced"
      , testCase "handles all quote types together" $
          sanitizeForYaml "it's a \"test\" with `code`" @?= "its a test with code"
      ]
  , testGroup "isPostFile (extended)"
      [ testCase "rejects exactly 10 chars without .md suffix" $
          isPostFile "2024-01-15" @?= False
      , testCase "accepts digit-only month even if out of range" $
          isPostFile "2024-13-15-post.md" @?= True
      , testCase "rejects missing day dash" $
          isPostFile "2024-0115-post.md" @?= False
      , testCase "accepts minimal dated file" $
          isPostFile "2024-01-01-x.md" @?= True
      , testCase "rejects IDEAS.md" $
          isPostFile "IDEAS.md" @?= False
      ]
  , testGroup "isContentFile"
      [ testCase "accepts dated markdown file" $
          isContentFile "2024-01-15-my-post.md" @?= True
      , testCase "accepts non-dated markdown file" $
          isContentFile "sapiens.md" @?= True
      , testCase "accepts kebab-case markdown file" $
          isContentFile "a-brief-history-of-time.md" @?= True
      , testCase "rejects index.md" $
          isContentFile "index.md" @?= False
      , testCase "rejects AGENTS.md" $
          isContentFile "AGENTS.md" @?= False
      , testCase "rejects IDEAS.md" $
          isContentFile "IDEAS.md" @?= False
      , testCase "rejects non-markdown files" $
          isContentFile "photo.jpg" @?= False
      , testCase "rejects empty string" $
          isContentFile "" @?= False
      ]
  , testGroup "isDateOnlyTitle"
      [ testCase "returns True when title matches date" $
          isDateOnlyTitle "---\ntitle: 2026-04-04\n---\n# 2026-04-04\nbody" "2026-04-04" @?= True
      , testCase "returns True for quoted date title" $
          isDateOnlyTitle "---\ntitle: \"2026-04-04\"\n---\nbody" "2026-04-04" @?= True
      , testCase "returns False for creative title" $
          isDateOnlyTitle "---\ntitle: \"2026-04-04 | Creative Title\"\n---\nbody" "2026-04-04" @?= False
      , testCase "returns False when title is empty" $
          isDateOnlyTitle "---\ntags: foo\n---\nbody" "2026-04-04" @?= False
      , testCase "returns False for non-date title" $
          isDateOnlyTitle "---\ntitle: My Post\n---\nbody" "2026-04-04" @?= False
      , testCase "returns True when H1 is the date" $
          isDateOnlyTitle "# 2026-04-04\nbody" "2026-04-04" @?= True
      , testCase "returns False when date does not match" $
          isDateOnlyTitle "---\ntitle: 2026-04-03\n---\nbody" "2026-04-04" @?= False
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
