(function () {
  "use strict";

  function setupCarousel(carousel) {
    const cards = Array.from(carousel.querySelectorAll("[data-writing-card]"));
    const previous = carousel.querySelector("[data-writing-previous]");
    const next = carousel.querySelector("[data-writing-next]");
    const status = carousel.querySelector("[data-writing-status]");

    if (!cards.length || !previous || !next || !status) return;

    let activeIndex = 0;

    function render() {
      cards.forEach(function (card, index) {
        const offset = (index - activeIndex + cards.length) % cards.length;
        card.classList.toggle("is-visible", offset === 0);
        card.classList.toggle("is-next", offset === 1);
        card.classList.toggle("is-next-next", offset === 2);
        card.setAttribute("aria-hidden", offset === 0 ? "false" : "true");
      });

      status.textContent = (activeIndex + 1) + " / " + cards.length;
    }

    previous.addEventListener("click", function () {
      activeIndex = (activeIndex - 1 + cards.length) % cards.length;
      render();
    });

    next.addEventListener("click", function () {
      activeIndex = (activeIndex + 1) % cards.length;
      render();
    });

    carousel.addEventListener("keydown", function (event) {
      if (event.key === "ArrowLeft") previous.click();
      if (event.key === "ArrowRight") next.click();
    });

    render();
  }

  function init() {
    document.querySelectorAll("[data-writing-carousel]").forEach(setupCarousel);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
