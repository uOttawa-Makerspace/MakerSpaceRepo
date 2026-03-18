// Keeps the thumbnail strip in sync with Bootstrap carousel slides
// and pauses any YouTube embed when the user slides away from it.

let ytAPIReady = false;
const ytPlayers = {}; // keyed by iframe id

// ── YouTube iFrame API bootstrap ──────────────────────────────────
function loadYouTubeAPI() {
  if (window.YT && window.YT.Player) {
    ytAPIReady = true;
    return;
  }
  if (document.querySelector('script[src*="youtube.com/iframe_api"]')) return;

  const tag = document.createElement("script");
  tag.src = "https://www.youtube.com/iframe_api";
  const first = document.getElementsByTagName("script")[0];
  first.parentNode.insertBefore(tag, first);
}

// Global callback the YT script looks for
window.onYouTubeIframeAPIReady = () => {
  ytAPIReady = true;
  wrapExistingIframes();
};

// Wrap every .youtube-embed iframe already in the DOM
function wrapExistingIframes() {
  document.querySelectorAll("iframe.youtube-embed").forEach((iframe) => {
    if (!iframe.id || ytPlayers[iframe.id]) return;
    ytPlayers[iframe.id] = new YT.Player(iframe.id);
  });
}

// ── Pause helper ──────────────────────────────────────────────────
function pauseAllYTPlayersIn(slide) {
  if (!slide) return;
  slide.querySelectorAll("iframe.youtube-embed").forEach((iframe) => {
    const player = ytPlayers[iframe.id];
    if (player && typeof player.pauseVideo === "function") {
      player.pauseVideo();
    }
  });
}

// ── Carousel + thumbnail init ─────────────────────────────────────
function initCarouselThumbnails() {
  const carousel = document.getElementById("repositoryCarousel");
  if (!carousel) return;

  // Load / re-wrap after Turbo navigations
  loadYouTubeAPI();
  if (ytAPIReady) wrapExistingIframes();

  const thumbnails = document.querySelectorAll(".carousel-thumbnail");

  carousel.addEventListener("slide.bs.carousel", (e) => {
    // Pause the YouTube video on the slide we're leaving
    pauseAllYTPlayersIn(
      e.relatedTarget?.parentElement
        ? carousel.querySelectorAll(".carousel-item")[e.from]
        : null,
    );
    // More reliable: grab the "from" slide directly
    const slides = carousel.querySelectorAll(".carousel-item");
    if (slides[e.from]) pauseAllYTPlayersIn(slides[e.from]);

    // Sync thumbnails
    if (!thumbnails.length) return;
    thumbnails.forEach((t) => t.classList.remove("active"));
    if (thumbnails[e.to]) {
      thumbnails[e.to].classList.add("active");
      thumbnails[e.to].scrollIntoView({
        behavior: "smooth",
        block: "nearest",
        inline: "center",
      });
    }
  });
}

// ── Boot ───────────────────────────────────────────────────────────
document.addEventListener("turbo:load", initCarouselThumbnails);
if (document.readyState !== "loading") {
  initCarouselThumbnails();
} else {
  document.addEventListener("DOMContentLoaded", initCarouselThumbnails);
}
