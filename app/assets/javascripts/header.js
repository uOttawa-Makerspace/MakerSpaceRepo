$(document).on('ready page:load', function () {
    var nav = $('nav.navbar');
    var chevron = $('.down-indicator');

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
        if ($(this).scrollTop() > 0) {
            chevron.css('opacity', 0);
            doTransition('bg-light navbar-light');
        } else {
            chevron.css('opacity', 1);
            doTransition('navbar-dark');
        }
    }).trigger('scroll');
});
