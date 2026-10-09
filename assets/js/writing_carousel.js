(function () {
  "use strict";

  document.querySelectorAll("[data-carousel]").forEach(function (carousel) {
    const track = carousel.querySelector(".writing-carousel-track");
    const previous = carousel.querySelector(".writing-carousel-previous");
    const next = carousel.querySelector(".writing-carousel-next");
    const status = carousel.querySelector(".writing-carousel-status");
    const cards = Array.from(track.querySelectorAll(".writing-card"));
    const pageSize = 3;
    let page = 0;

    function render() {
      const totalPages = Math.max(1, Math.ceil(cards.length / pageSize));
      const start = page * pageSize + 1;
      const end = Math.min((page + 1) * pageSize, cards.length);
      track.style.transform = "translateX(-" + page * 100 + "%)";
      status.textContent = start + "–" + end + " of " + cards.length;
      previous.disabled = page === 0;
      next.disabled = page >= totalPages - 1;
      previous.setAttribute("aria-label", previous.disabled ? "No previous articles" : "Show previous articles");
      next.setAttribute("aria-label", next.disabled ? "No more articles" : "Show next articles");
    }

    previous.addEventListener("click", function () {
      if (page > 0) {
        page -= 1;
        render();
      }
    });

    next.addEventListener("click", function () {
      const totalPages = Math.ceil(cards.length / pageSize);
      if (page < totalPages - 1) {
        page += 1;
        render();
      }
    });

    render();
  });
})();
