/**
 * Home page responsive font sizing
 * Detects screen size and adjusts font to fit content within the viewport
 */
(function () {
  "use strict";

  const MIN_FONT_SIZE = 10;
  const MAX_FONT_SIZE = 24;
  const INITIAL_FONT_SIZE = 16;

  function fitContentToViewport() {
    const wrapper = document.querySelector(".w");
    if (!wrapper) return;

    const viewportHeight = window.innerHeight;
    const viewportWidth = window.innerWidth;

    // Start with a reasonable font size
    let fontSize = INITIAL_FONT_SIZE;
    document.body.style.fontSize = fontSize + "px";

    // Get the content dimensions
    const content = wrapper;

    // Binary search for optimal font size
    let low = MIN_FONT_SIZE;
    let high = MAX_FONT_SIZE;
    let optimalSize = INITIAL_FONT_SIZE;

    while (low <= high) {
      const mid = Math.floor((low + high) / 2);
      document.body.style.fontSize = mid + "px";

      // Force reflow to get accurate measurements
      content.offsetHeight;

      const contentHeight = content.scrollHeight;
      const contentWidth = content.scrollWidth;

      // Check if content fits within viewport (with some padding)
      const fitsHeight = contentHeight <= viewportHeight * 0.9;
      const fitsWidth = contentWidth <= viewportWidth * 0.95;

      if (fitsHeight && fitsWidth) {
        optimalSize = mid;
        low = mid + 1; // Try larger
      } else {
        high = mid - 1; // Try smaller
      }
    }

    // Apply the optimal font size
    document.body.style.fontSize = optimalSize + "px";
  }

  // Run on page load
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", fitContentToViewport);
  } else {
    fitContentToViewport();
  }

  // Run on resize with debouncing
  let resizeTimeout;
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(fitContentToViewport, 150);
  });

  // Also run after fonts are loaded
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(fitContentToViewport);
  }
})();
