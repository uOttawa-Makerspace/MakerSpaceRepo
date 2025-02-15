import PhotoSwipeLightbox from "photoswipe/lightbox";
import "photoswipe/style.css";

document.addEventListener("turbo:load", function () {
  const lightbox = new PhotoSwipeLightbox({
    gallery: "#photo-slide",
    children: "img",
    bgOpacity: 0.7,
    wheelToZoom: true,
    hideAnimationDuration: 0,
    showAnimationDuration: 0,
    zoomAnimationDuration: 100,
    pswpModule: () => import("photoswipe"),
  });

  // Grab data from each image
  lightbox.addFilter("itemData", (itemData, index) => {
    return {
      src: itemData.element.src,
      width: itemData.element.dataset.width,
      height: itemData.element.dataset.height,
    };
  });

  // Add a handler to the big image
  const bigImage = document.querySelector("#show-photo img");
  if (bigImage) {
    bigImage.addEventListener("click", function () {
      lightbox.loadAndOpen(0);
    });
  }
  // TODO add captions
  lightbox.init();
});
