$(document).on('ready page:load', function () {
    var nav = $('nav.navbar');
    var chevron = $('.down-indicator');
    var collapse = nav.find('.navbar-collapse');
    var background = $('<div class="background">');
    var cc_image_white = document.getElementById("myCcWhite");
    var cc_image_black = document.getElementById("myCcBlack");

    function doTransition(dark, animate) {
        if (typeof animate === 'undefined' || animate === true) {
            nav.addClass('transition');
        }

        if (dark) {
            nav.removeClass('navbar-light');
            background.removeClass('bg-light');
            nav.addClass('navbar-dark');
            cc_image_white.style.display = 'inline';
            cc_image_black.style.display = 'none';
        } else {
            nav.removeClass('navbar-dark');
            nav.addClass('navbar-light');
            background.addClass('bg-light');
            cc_image_white.style.display = 'none';
            cc_image_black.style.display = 'inline';
        }
    }

    if (!nav.hasClass('static_pages home')) {
        return;
    }

    nav.removeClass('bg-light');
    nav.addClass('bg-dark-gradient');
    nav.append(background);

    nav.on('transitionend webkitTransitionEnd oTransitionEnd otransitionend MSTransitionEnd', function () {
        nav.removeClass('transition');
    });

    collapse.on('show.html.erb.bs.collapse hide.bs.collapse', function () {
        doTransition(nav.hasClass('static_pages home') && $(window).scrollTop() <= 10 && collapse.hasClass('show.html.erb'));
    });

    $(window).on('scroll', function () {
        doTransition(nav.hasClass('static_pages home') && $(window).scrollTop() <= 10 && !collapse.hasClass('show.html.erb'));

        if ($(window).scrollTop() <= 10) {
            chevron.css('opacity', 1);
        } else {
            chevron.css('opacity', 0);
        }
    });

    doTransition(true, false);
});
