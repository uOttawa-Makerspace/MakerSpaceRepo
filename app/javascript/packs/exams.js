jQuery( document ).ready(function( $ ) {
    //Use this inside your document ready jQuery
    $(window).on('popstate', function() {
        location.reload(true);
    });

});