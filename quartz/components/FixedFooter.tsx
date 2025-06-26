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
// quartz/styles/custom.scss

// ... (your existing styles in this file) ...

// --- FOOTER STYLES (Moved from FixedFooter.tsx) ---
.fixed-cta-footer {
  position: fixed !important;
  bottom: 0 !important;
  left: 0 !important;
  width: 100% !important;
  background-color: var(--highlight) !important; /* <--- CHANGED THIS LINE to --highlight */
  border-top: 1px solid var(--border) !important; /* This is where you can change to var(--orange) or var(--red) if desired later */
  padding: clamp(0.6em, 2vw, 0.8em) clamp(0.5em, 2vw, 1em) !important;
  display: flex !important;
  flex-direction: column !important;
  align-items: center !important;
  gap: 0.5em !important;
  z-index: 1000 !important;
  box-shadow: 0 -2px 10px rgba(0,0,0,0.1) !important;
}

.fixed-cta-footer .cta-button {
  display: block !important;
  background-color: transparent !important;
  color: var(--link) !important;
  border: 1px solid var(--link) !important;
  padding: clamp(0.6em, 2vw, 0.7em) clamp(1em, 4vw, 1.5em) !important;
  border-radius: 8px !important;
  text-decoration: none !important;
  font-weight: bold !important;
  font-size: clamp(1em, 2.5vw, 1.1em) !important;
  text-align: center !important;
  transition: background-color 0.2s ease-in-out, color 0.2s ease-in-out, border-color 0.2s ease-in-out !important;
  width: 100% !important;
  max-width: 300px !important;
}

.fixed-cta-footer .cta-button:hover {
  background-color: var(--link) !important;
  color: var(--light) !important; /* <--- CHANGED THIS LINE to --light for contrast */
  border-color: var(--link) !important;
  filter: none !important;
}

.fixed-cta-footer .affiliate-text {
  font-size: 0.75em !important;
  color: var(--text-muted) !important; /* Assuming --text-muted exists and works for affiliate text */
  text-align: center !important;
  margin: 0 !important;
}
  `
  return FixedFooterComponent
}) satisfies QuartzComponentConstructor

export default FixedFooter