var photoArray = [];

document.addEventListener("DOMContentLoaded", function () {
    photoArray = [];
    let gallery = photoSwipe();
    let photoSlide = document.getElementById('photo-slide');
    if (photoSlide) {
        photoSlide.childNodes.forEach(function (node) {
            let img = node;
            if (img.tagName === 'IMG') {
                photoArray.push({
                    src: img.getAttribute('src'),
                    w: img.getAttribute('data-width'),
                    h: img.getAttribute('data-height')
                });
                img.addEventListener('click', function () {
                    gallery.options.index = img.index();
                    gallery.init();
                });
            }
        });
    }
    let showPhoto = document.getElementById('show-photo');
    if (showPhoto) {
        showPhoto.addEventListener('click', function () {
            gallery.init();
        });
    }
});

function photoSwipe() {
    var pswpElement = document.querySelectorAll('.pswp')[0];

    var items = photoArray;
    var options = {
        index: 0
    };

    var gallery = new PhotoSwipe(pswpElement, PhotoSwipeUI_Default, items, options);
    return gallery;
}


