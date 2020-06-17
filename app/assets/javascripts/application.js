// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or any plugin's vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
// Do not add libraries from gems here! Put them in vendor/assets/javascripts/vendor.js instead.
//
//= require jquery
//= require popper
//= require bootstrap-sprockets
//= require jquery_ujs
//= require jquery-ui/autocomplete
//= require photoswipe
//= require jquery-ui/effect.all
//= require turbolinks
//= require clipboard
//= require bootbox
//= require s3_direct_upload
//= require toastr
//= require trix
//= require select2-full
//= require_tree .

// Turbolinks.enableProgressBar();

// needed since by default bootstrap-select doesn't register page:load events
$(document).on('turbolinks:load', function () {
    $('[data-radio-enable]').on('change', function () {
        var $inputs = $('input[type="radio"][name="' + $(this).attr('name') + '"]');

        $inputs.each(function () {
            var $input = $(this);
            var $target = $($input.data('radio-enable'));

            if ($input.prop('checked')){
                $target.prop('disabled', false);
            } else {
                $target.prop('disabled', true);
            }
        });
    }).trigger('change');

    $('.bootstrap-select').selectpicker({
        windowPadding: [80, 0, 0, 0]
    });
});

$(document).ready(function(){

    var clipboard = new Clipboard('.clipboard-btn');
    console.log(clipboard);

});