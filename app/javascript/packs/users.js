$(document).on("turbolinks:load", function() {
    $("[data-show]").on('change', function () {
        var selector = $(this).data('show');
        var show = $(this).prop('checked');

        if (show) {
            $(selector).css('display', 'block');
        }
    }).each(function () {
        if ($(this).prop('checked')) {
            $(this).trigger('change');
        }
    });

    $("[data-hide]").on('change', function () {
        var selector = $(this).data('hide');
        var hide = $(this).prop('checked');

        if (hide) {
            $(selector).css('display', 'none');
        }
    }).each(function () {
        if ($(this).prop('checked')) {
            $(this).trigger('change');
        }
    });
});