jQuery( document ).ready(function( $ ) {
    //Use this inside your document ready jQuery
    $(window).on('popstate', function() {
        location.reload(true);
    });
});

$(document).on("turbolinks:load", function () {
    $("#questionImageGallery").justifiedGallery({
        rowHeight: 250,
        lastRow: 'center'
    });

});
