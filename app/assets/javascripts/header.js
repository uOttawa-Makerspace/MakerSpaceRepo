$(document).on('ready page:load', function () {
    var nav = $('nav.navbar');

    function doTransition(to) {
        nav.removeClass('navbar-dark navbar-light bg-light');
        nav.addClass('transition');
        nav.addClass(to);
    }

    if (!nav.hasClass('static_pages home')) {
        doTransition('bg-light navbar-light');
        return;
    }

    nav.on('transitionend webkitTransitionEnd oTransitionEnd otransitionend MSTransitionEnd', function () {
        nav.removeClass('transition');
    });

    $(window).on('scroll', function () {
        console.log('scroll');
        if ($(this).scrollTop() > 0) {
            doTransition('bg-light navbar-light');
        } else {
            doTransition('navbar-dark');
        }
    }).trigger('scroll');
});
