import { QuartzConfig } from "./quartz/cfg"
import * as Plugin from "./quartz/plugins"

const SOLARIZED = {
  base03: '#002b36',
  base02: '#073642',
  base01: '#586e75',
  base00: '#657b83',
  base0: '#839496',
  base1: '#93a1a1',
  base2: '#eee8d5',
  base3: '#fdf6e3',
  yellow: '#b58900',
  orange: '#cb4b16',
  red: '#dc322f',
  magenta: '#d33682',
  violet: '#6c71c4',
  blue: '#268bd2',
  cyan: '#2aa198',
  green: '#859900'
}

/**
 * Quartz 4.0 Configuration
 *
 * See https://quartz.jzhao.xyz/configuration for more information.
 */
const config: QuartzConfig = {
  configuration: {
    pageTitle: "bagrounds.org",
    enableSPA: true,
    enablePopovers: true,
    analytics: {
      provider: "google",
      tagId: "G-8Q69PH85GH",
    },
    locale: "en-US",
    baseUrl: "bagrounds.org",
    ignorePatterns: ["private", "templates", ".obsidian"],
    defaultDateType: "modified",
    theme: {
      fontOrigin: "googleFonts",
      cdnCaching: true,
      typography: {
        header: "Schibsted Grotesk",
        body: "Source Sans Pro",
        code: "IBM Plex Mono",
      },
      colors: {
        lightMode: {
          light: SOLARIZED.base3,
          lightgray: SOLARIZED.base1,
          gray: SOLARIZED.orange,
          darkgray: SOLARIZED.base01,
          dark: SOLARIZED.cyan,
          secondary: SOLARIZED.blue,
          tertiary: SOLARIZED.base00,
          highlight: SOLARIZED.base2,
          textHighlight: SOLARIZED.base2,
        },
        darkMode: {
          light: SOLARIZED.base03,
          lightgray: SOLARIZED.base01,
          gray: SOLARIZED.orange,
          darkgray: SOLARIZED.base1,
          dark: SOLARIZED.cyan,
          secondary: SOLARIZED.blue,
          tertiary: SOLARIZED.base0,
          highlight: SOLARIZED.base02,
          textHighlight: SOLARIZED.base02,
        },
      },
    },
  },
  plugins: {
    transformers: [
      Plugin.FrontMatter(),
      Plugin.CreatedModifiedDate({
        priority: ["frontmatter", "git", "filesystem"],
      }),
      Plugin.Latex({ renderEngine: "katex" }),
      Plugin.SyntaxHighlighting({
        theme: {
          light: "github-light",
          dark: "github-dark",
        },
        keepBackground: false,
      }),
      Plugin.ObsidianFlavoredMarkdown({ enableInHtmlEmbed: false }),
      Plugin.GitHubFlavoredMarkdown(),
      Plugin.TableOfContents(),
      Plugin.CrawlLinks({ markdownLinkResolution: "relative" }),
      Plugin.Description(),
    ],
    filters: [Plugin.RemoveDrafts()],
    emitters: [
      Plugin.AliasRedirects(),
      Plugin.ComponentResources(),
      Plugin.ContentPage(),
      Plugin.CustomOgImages({
        colorScheme: "darkMode", // what colors to use for generating image, same as theme colors from config, valid values are "darkMode" and "lightMode"
        width: 1200, // width to generate with (in pixels)
        height: 630, // height to generate with (in pixels)
        excludeRoot: false, // wether to exclude "/" index path to be excluded from auto generated images (false = use auto, true = use default og image)
        // imageStructure: defaultImage, // custom image component to use
      }),
      Plugin.FolderPage(),
      Plugin.TagPage(),
      Plugin.ContentIndex({
        enableSiteMap: true,
        enableRSS: true,
        rssLimit: 1000,
        rssFullHtml: true,
      }),
      Plugin.Assets(),
      Plugin.Static(),
      Plugin.NotFoundPage(),
    ],
  },
}

export default config
