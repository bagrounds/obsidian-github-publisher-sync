import { QuartzComponent, QuartzComponentConstructor, QuartzComponentProps } from "./types"
import { h } from "preact" // Explicitly import Preact's createElement function

// Define the FixedFooter component
const FixedFooter: QuartzComponent = ((opts?: {}) => { // Use 'opts' for any future configuration
  const FixedFooterComponent: QuartzComponent = ({ fileData }: QuartzComponentProps) => {
    // Get Amazon link and book title from frontmatter
    const amazonLink = fileData.frontmatter?.["affiliate link"] as string | undefined
    const bookTitle = fileData.frontmatter?.title as string | undefined

    // Only render if the 'amazon' link and 'title' are present in frontmatter
    if (!amazonLink || !bookTitle) {
      return null // Don't render if the required data is missing
    }

    const buttonText = `🛒 Get "${bookTitle}" on Amazon`
    const affiliateDisclosure = "As an Amazon Associate I earn from qualifying purchases."

    return (
      <div class="fixed-cta-footer"> {/* Use class for HTML attributes in Preact/JSX */}
        <a href={amazonLink} class="cta-button" target="_blank" rel="noopener noreferrer">
          {buttonText}
        </a>
        <p class="affiliate-text">{affiliateDisclosure}</p>
      </div>
    )
  }

  // Assign the CSS to the component's `css` property
  FixedFooterComponent.css = `
    .fixed-cta-footer {
      position: fixed;
      bottom: 0;
      left: 0;
      width: 100%;
      background-color: var(--background-secondary); /* Use your theme's background color */
      border-top: 1px solid var(--border);
      padding: 0.8em 1em;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5em;
      z-index: 1000; /* Ensure it stays above other content */
      box-shadow: 0 -2px 10px rgba(0,0,0,0.1); /* Subtle shadow */
    }

    .fixed-cta-footer .cta-button {
      display: block;
      background-color: #FF9900; /* Amazon orange or your primary brand color */
      color: white;
      padding: 0.7em 1.5em;
      border-radius: 8px; /* More rounded corners */
      text-decoration: none;
      font-weight: bold;
      font-size: 1.1em;
      text-align: center;
      transition: background-color 0.2s ease-in-out;
      width: 100%; /* Make button full width on smaller screens */
      max-width: 300px; /* Max width for desktop */
    }

    .fixed-cta-footer .cta-button:hover {
      background-color: #e68a00; /* Darker orange on hover */
    }

    .fixed-cta-footer .affiliate-text {
      font-size: 0.75em;
      color: var(--text-muted);
      text-align: center;
      margin: 0;
    }

    /* Responsive adjustments for mobile */
    @media (max-width: 768px) {
      .fixed-cta-footer {
        padding: 0.6em 0.5em; /* Reduce padding on smaller screens */
      }
      .fixed-cta-footer .cta-button {
        font-size: 1em;
        padding: 0.6em 1em;
      }
    }
  `
  return FixedFooterComponent
}) satisfies QuartzComponentConstructor

export default FixedFooter // Export default for easier import