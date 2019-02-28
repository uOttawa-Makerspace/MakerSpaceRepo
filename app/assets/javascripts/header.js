$(document).on('ready page:load', function () {
    console.log('page load');

    var nav = $('nav.navbar');

    if (!nav.hasClass('static_pages home')) {
        nav.removeClass('navbar-dark');
        nav.addClass('bg-light', 'navbar-light');
        return;
    }

    $(window).on('scroll', function () {
        console.log('scroll');
        if ($(this).scrollTop() > 0) {
            nav.removeClass('navbar-dark');
            nav.addClass('bg-light', 'navbar-light');
        } else {
            nav.removeClass('bg-light', 'navbar-light');
            nav.addClass('navbar-dark');
        }
    }).trigger('scroll');
});