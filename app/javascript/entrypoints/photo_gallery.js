import PhotoSwipe from "photoswipe";

document.addEventListener("DOMContentLoaded", function () {
  const pswpElement = document.querySelectorAll(".pswp")[0];
  const imageGallery = document.getElementById("photo-slide");
  let images = [];
  let image_tags = [];

  const parseImages = function (el) {
    if (el) {
      const childNodes = el.children;
      let items = [];

      if (childNodes === undefined) {
        return;
      }

      Array.from(childNodes).forEach(function (node, index) {
        if (node.tagName === "IMG") {
          const item = {
            src: node.src,
            w: node.getAttribute("data-width"),
            h: node.getAttribute("data-height"),
          };
          items.push(item);
          image_tags.push(node);

          node.addEventListener("click", () => openPhotoSwipe(index));
        }
      });

      images = items;

      const mainImageDiv = document.getElementById("show-photo");

      if (
        mainImageDiv &&
        mainImageDiv.children[0] &&
        mainImageDiv.children[0].tagName === "IMG"
      ) {
        mainImageDiv.children[0].addEventListener("click", () =>
          openPhotoSwipe(0),
        );
      }
    }
  };

  const openPhotoSwipe = function (startIndex) {
    const options = {
      index: startIndex,
      getThumbBoundsFn: function (index) {
        const currentImage = image_tags[index];
        const pageYScroll =
          window.scrollY || document.documentElement.scrollTop;
        const boundingRect = currentImage.getBoundingClientRect();

        const rect = {
          x: boundingRect.left,
          y: boundingRect.top + pageYScroll,
          w: boundingRect.width,
        };

        return rect;
      },
      bgOpacity: 0.7,
    };

    let gallery = new PhotoSwipe(
      pswpElement,
      PhotoSwipeUI_Default,
      images,
      options,
    );

    gallery.init();
  };

  parseImages(imageGallery);
});
