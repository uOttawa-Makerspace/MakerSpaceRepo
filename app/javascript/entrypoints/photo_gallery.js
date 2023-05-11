import PhotoSwipe from "photoswipe";
import PhotoSwipeUI_Default from "photoswipe/dist/photoswipe-ui-default";

document.addEventListener("DOMContentLoaded", function () {
  var images = [];
  var image_tags = [];

  var parseImages = function (el) {
    if (el) {
      var childNodes = el.children;
      var items = [];

      if (childNodes === undefined) {
        return;
      }

      Array.from(childNodes).forEach(function (node, index) {
        if (node.tagName === "IMG") {
          let item = {
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

      var mainImageDiv = document.getElementById("show-photo");
      if (
        mainImageDiv &&
        mainImageDiv.children[0] &&
        mainImageDiv.children[0].tagName === "IMG"
      ) {
        mainImageDiv.children[0].addEventListener("click", () =>
          openPhotoSwipe(0)
        );
      }
    }
  };

  var openPhotoSwipe = function (startIndex) {
    var options = {
      index: startIndex,
      getThumbBoundsFn: function (index) {
        var currentImage = image_tags[index];
        var pageYScroll = window.scrollY || document.documentElement.scrollTop;
        var boundingRect = currentImage.getBoundingClientRect();

        var rect = {
          x: boundingRect.left,
          y: boundingRect.top + pageYScroll,
          w: boundingRect.width,
        };

        return rect;
      },
      bgOpacity: 0.7,
    };

    var gallery = new PhotoSwipe(
      pswpElement,
      PhotoSwipeUI_Default,
      images,
      options
    );

    gallery.init();
  };

  parseImages(document.getElementById("photo-slide"));
  var pswpElement = document.querySelectorAll(".pswp")[0];
});
