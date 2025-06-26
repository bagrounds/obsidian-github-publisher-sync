import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"

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

    const buttonText = `🛒 Get "${bookTitle}" on Amazon`
    const affiliateDisclosure = "As an Amazon Associate I earn from qualifying purchases."
    // --- Inlined JavaScript Code ---
    // This script measures the footer's height and sets a CSS variable.
    // It runs after the DOM is fully loaded and on window resize.
    const inlineScript = `
      document.addEventListener('DOMContentLoaded', () => {
        const footer = document.getElementById('fixed-cta-footer');
        if (footer) {
          const updatePadding = () => {
            const footerHeight = footer.offsetHeight;

            // Calculate buffer based on the root font size (e.g., 1.5 times the base font size)
            // This makes the buffer responsive and less "guessed".
            const rootFontSize = parseFloat(getComputedStyle(document.documentElement).fontSize);
            const buffer = rootFontSize * 1.5; // You can adjust the 1.5 multiplier as needed (e.g., 1em, 2em)

            document.documentElement.style.setProperty('--fixed-footer-height', (footerHeight + buffer) + 'px');
          };

          // Set padding initially
          updatePadding();

          // Update padding on window resize (footer height might change due to text wrapping)
          window.addEventListener('resize', updatePadding);
        }
      });
    `;
    return (
<>
      <div id="fixed-cta-footer" class="fixed-cta-footer">
        <a href={affiliateLink} class="cta-button" target="_blank" rel="noopener noreferrer">
          {buttonText}
        </a>
        <p class="affiliate-text">{affiliateDisclosure}</p>
      </div>
      <script dangerouslySetInnerHTML={{ __html: inlineScript }} />
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
      background-color: var(--background-secondary);
      border-top: 1px solid var(--border);
      padding: clamp(0.6em, 2vw, 0.8em) clamp(0.5em, 2vw, 1em);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5em;
      z-index: 1000;
      box-shadow: 0 -2px 10px rgba(0,0,0,0.1);
    }

    .fixed-cta-footer .cta-button {
      display: block;
      background-color: transparent;
      color: var(--link);
      border: 1px solid var(--link);
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
      color: var(--background-secondary);
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