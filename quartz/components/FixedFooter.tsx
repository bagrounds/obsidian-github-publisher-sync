import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"

function removeEmojis(str: string): string {
  return str.replace(/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{1F900}-\u{1F9FF}\u{1FA70}-\u{1FAFF}\u{200d}\u{23CF}\u{23E9}\u{23FA}\u{2B05}\u{2B06}\u{2B07}\u{2B1B}\u{2B1C}\u{2B50}\u{2B55}\u{3030}\u{303D}\u{3297}\u{3299}\u{1F004}\u{1F0CF}\u{1F170}\u{1F171}\u{1F17E}\u{1F17F}\u{1F18E}\u{1F191}-\u{1F19A}\u{1F201}\u{1F202}\u{1F21A}\u{1F22F}\u{1F232}\u{1F233}\u{1F23A}\u{1F250}\u{1F251}\u{2122}\u{2139}\u{2194}-\u{2199}\u{21A9}-\u{21AA}\u{231A}\u{231B}\u{25AA}\u{25AB}\u{25B6}\u{25C0}\u{25FB}-\u{25FE}\u{2600}-\u{2601}\u{260E}\u{2611}\u{2614}-\u{2615}\u{2618}\u{261D}\u{2620}\u{2622}-\u{2623}\u{2626}\u{262A}\u{262E}-\u{262F}\u{2638}-\u{263A}\u{2640}\u{2642}\u{2648}-\u{2653}\u{2660}\u{2663}\u{2665}-\u{2666}\u{2668}\u{267B}\u{267F}\u{2692}-\u{2694}\u{2696}-\u{2697}\u{2699}\u{269B}-\u{269C}\u{26A0}-\u{26A1}\u{26AA}-\u{26AB}\u{26B0}-\u{26B1}\u{26BD}-\u{26BE}\u{26C4}-\u{26C5}\u{26CE}\u{26D4}\u{26EA}\u{26F0}-\u{26F5}\u{26F7}-\u{26FA}\u{26FD}\u{2702}\u{2705}\u{2708}-\u{270D}\u{270F}\u{2712}\u{2714}\u{2716}\u{271D}\u{2721}\u{2733}-\u{2734}\u{274C}\u{274E}\u{2753}-\u{2755}\u{2757}\u{2763}-\u{2764}\u{2795}-\u{2797}\u{27A1}\u{27B0}\u{27BF}\u{2934}-\u{2935}\u{2B05}-\u{2B07}\u{2B1B}-\u{2B1C}\u{2B50}\u{2B55}\u{3030}\u{303D}\u{3297}\u{3299}\ufe0e\ufe0f]/gu, '');
}

// Define the FixedFooter component
const FixedFooter: QuartzComponent = ((opts?: {}) => {
  const FixedFooterComponent: QuartzComponent = ({ fileData }: QuartzComponentProps) => {
    // Get Amazon link and book title from frontmatter
    const affiliateLink = fileData.frontmatter?.["affiliate link"] as string | undefined
    const bookTitle = fileData.frontmatter?.title as string | undefined

    // Only render if the 'affiliate link' and 'title' are present in frontmatter
    if (!affiliateLink || !bookTitle) {
      return null // Don't render if the required data is missing
    }

    const buttonText = `🛒 Get ${bookTitle.replace(/:.*$/, '')} on Amazon`
    const affiliateDisclosure = "As an Amazon Associate I earn from qualifying purchases."

    return (
      <>
        <div class="fixed-cta-footer">
          <a href={affiliateLink} class="cta-button" target="_blank" rel="noopener noreferrer">
            {buttonText}
          </a>
          <p class="affiliate-text">{affiliateDisclosure}</p>
        </div>
      </>
    )
  }

  // Assign the CSS to the component's `css` property
  FixedFooterComponent.css = `
    .fixed-cta-footer {
      position: fixed;
      bottom: 0;
      left: 0;
      width: 100%;
      background-color: var(--light) !important; /* <--- CRITICAL TEST: Changed to white and added !important */
      border-top: 1px solid var(--gray);
      padding: clamp(0.6em, 1.5vw, 0.8em) clamp(0.5em, 1.5vw, 1em);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5em;
      z-index: 1000;
      box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
    }

    .fixed-cta-footer .cta-button {
      display: block;
      background-color: var(--highlight);
      border: 1px solid var(--gray);
      padding: clamp(0.6em, 2vw, 0.7em) clamp(1em, 4vw, 1.5em);
      border-radius: 8px;
      text-decoration: none;
      font-weight: bold;
      font-size: clamp(1em, 2.5vw, 1.1em);
      text-align: center;
      transition: background-color 0.2s ease-in-out, color 0.2s ease-in-out, border-color 0.2s ease-in-out;
      width: 100%;
      max-width: 300px;
    }

    .fixed-cta-footer .cta-button:hover {
      background-color: var(--link);
      color: var(--highlight);
      border-color: var(--link);
      filter: none;
    }

    .fixed-cta-footer .affiliate-text {
      font-size: 0.75em;
      color: var(--text-muted);
      text-align: center;
      margin: 0;
    }
  `
  return FixedFooterComponent
}) satisfies QuartzComponentConstructor

export default FixedFooter