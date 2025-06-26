import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"

// Define the FixedFooter component
const FixedFooter: QuartzComponent = ((opts?: {}) => { // Use 'opts' for any future configuration
  const FixedFooterComponent: QuartzComponent = ({ fileData }: QuartzComponentProps) => {
    // Get Amazon link and book title from frontmatter
    const affiliateLink = fileData.frontmatter?.["affiliate link"] as string | undefined // Corrected property name
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
            document.documentElement.style.setProperty('--fixed-footer-height', \`${footerHeight}px\`);
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
      <div class="fixed-cta-footer"> {/* Use class for HTML attributes in Preact/JSX */}
        <a href={affiliateLink} class="cta-button" target="_blank" rel="noopener noreferrer"> {/* Using corrected link variable */}
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
      border-top: 1px solid var(--border);
      /* Fluid padding: scales between 0.6em and 0.8em vertically, 0.5em and 1em horizontally */
      /* These 'vw' values are suggestions and might need fine-tuning for your specific design */
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
      /* Fluid padding for the button itself */
      padding: clamp(0.6em, 2vw, 0.7em) clamp(1em, 4vw, 1.5em);
      border-radius: 8px;
      text-decoration: none;
      font-weight: bold;
      /* Fluid font-size for the button text */
      font-size: clamp(1em, 2.5vw, 1.1em);
      text-align: center;
      transition: background-color 0.2s ease-in-out, filter 0.2s ease-in-out;
      width: 100%; /* Ensures it takes full width on small screens */
      max-width: 300px; /* Caps its width on larger screens */
    }

    .fixed-cta-footer .cta-button:hover {
      filter: brightness(0.9);
    }

    .fixed-cta-footer .affiliate-text {
      font-size: 0.75em; /* This small fixed font size is usually fine across devices */
      text-align: center;
      margin: 0;
    }
  `
  return FixedFooterComponent
}) satisfies QuartzComponentConstructor

export default FixedFooter // Export default for easier import