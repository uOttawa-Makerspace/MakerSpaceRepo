var photoArray = [];

$(document).on('turbolinks:load', function(){

    photoArray = [];
    var gallery = photoSwipe();

    $("div#photo-slide").children().each(function(){
        var img = $(this);
        photoArray.push({
            src: img.attr('src'),
            w: img.data().width,
            h: img.data().height
        });

        img.click(function(){
            gallery.options.index = img.index();
            gallery.init();
        });
    });


    $("div#show-photo").click(function(){
        gallery.init();
    });

});

function photoSwipe(){
    var pswpElement = document.querySelectorAll('.pswp')[0];

    var items = photoArray;
    var options = {
        index: 0
    };

    var gallery = new PhotoSwipe( pswpElement, PhotoSwipeUI_Default, items, options);
    return gallery;
}


