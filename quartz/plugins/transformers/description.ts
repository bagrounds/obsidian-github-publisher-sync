import { Root as HTMLRoot } from "hast"
import { toString } from "hast-util-to-string"
import { QuartzTransformerPlugin } from "../types"
import { escapeHTML } from "../../util/escape"

export interface Options {
  descriptionLength: number
  maxDescriptionLength: number
  replaceExternalLinks: boolean
}

const defaultOptions: Options = {
  descriptionLength: 720,
  maxDescriptionLength: 720,
  replaceExternalLinks: true,
}

const urlRegex = new RegExp(
  /(https?:\/\/)?(?<domain>([\da-z\.-]+)\.([a-z\.]{2,6})(:\d+)?)(?<path>[\/\w\.-]*)(\?[\/\w\.=&;-]*)?/,
  "g",
)

function removeTitle(textContent: string, pageTitle: string): string {
  const cleanedTitleSegments = pageTitle.split(/[^a-zA-Z0-9\s]/);
  const longestCleanTitleSegment = cleanedTitleSegments.reduce((longest, current) => {
    return current.length > longest.length ? current : longest;
  }, "");

  if (!longestCleanTitleSegment) {
    return textContent;
  }

  const cleanTitleIndex = textContent.indexOf(longestCleanTitleSegment);

  if (cleanTitleIndex === -1) {
    return textContent;
  }

  const newlineIndexAfterCleanTitle = textContent.indexOf('\n', cleanTitleIndex + longestCleanTitleSegment.length);

  if (newlineIndexAfterCleanTitle === -1) {
    return textContent;
  }

  return textContent.substring(newlineIndexAfterCleanTitle + 1);
}


export const Description: QuartzTransformerPlugin<Partial<Options>> = (userOpts) => {
  const opts = { ...defaultOptions, ...userOpts }
  return {
    name: "Description",
    htmlPlugins() {
      return [
        () => {
          return async (tree: HTMLRoot, file) => {
            let frontMatterDescription = file.data.frontmatter?.description
            let text = removeTitle(escapeHTML(toString(tree)), file.data.frontmatter?.title)
            const AFFILIATE_TEXT = 'As an Amazon Associate I earn from qualifying purchases.'

            let affiliateLessText = text.split(AFFILIATE_TEXT).?[1]
            text = affiliateLessText || text

            if (opts.replaceExternalLinks) {
              frontMatterDescription = frontMatterDescription?.replace(
                urlRegex,
                "$<domain>" + "$<path>",
              )
              text = text.replace(urlRegex, "$<domain>" + "$<path>")
            }

            if (frontMatterDescription) {
              file.data.description = frontMatterDescription
              file.data.text = text
              return
            }

            // otherwise, use the text content
            const desc = text.trim()
            const sentences = desc.replace(/(?<![.,?!:;])\n+/g,"; ").replace(/\s+/g, " ").split(/\.\s/)
            let finalDesc = ""
            let sentenceIdx = 0

            // Add full sentences until we exceed the guideline length
            while (sentenceIdx < sentences.length) {
              const sentence = sentences[sentenceIdx]
              if (!sentence) break

              const currentSentence = sentence.endsWith(".") ? sentence : sentence + "."
              const nextLength = finalDesc.length + currentSentence.length + (finalDesc ? 1 : 0)

              // Add the sentence if we're under the guideline length + sentence length
              // or if this is the first sentence (always include at least one)
              if (nextLength < (opts.descriptionLength + sentence.length) || sentenceIdx === 0) {
                finalDesc += (finalDesc ? " " : "") + currentSentence
                sentenceIdx++
              } else {
                break
              }
            }

            // truncate to max length if necessary
            file.data.description =
              finalDesc.length > opts.maxDescriptionLength
                ? finalDesc.slice(0, opts.maxDescriptionLength) + "..."
                : finalDesc
            file.data.text = text
          }
        },
      ]
    },
  }
}

declare module "vfile" {
  interface DataMap {
    description: string
    text: string
  }
}
