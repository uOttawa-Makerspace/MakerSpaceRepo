/* eslint no-console:0 */
// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.
//
// To reference this file, add <%= javascript_pack_tag 'application' %> to the appropriate
// layout file, like app/views/layouts/application.html.erb


// Uncomment to copy all static images under ../images to the output folder and reference
// them with the image_pack_tag helper in views (e.g <%= image_pack_tag 'rails.png' %>)
// or the `imagePath` JavaScript helper below.
//
// const images = require.context('../images', true)
// const imagePath = (name) => images(name, true)
import 'core-js/stable'
import 'regenerator-runtime/runtime'
require("@rails/ujs").start();
require("turbolinks").start();
require("@rails/activestorage").start();
require("jquery");
require("select2");
global.toastr = require("toastr");
global.Chart = require("chart.js");
require("trix");
require("@shopify/buy-button-js");
require("jquery-ui");
global.PhotoSwipe = require('photoswipe');
global.PhotoSwipeUI_Default = require('photoswipe/dist/photoswipe-ui-default');
var Clipboard = require("clipboard");
require("bootbox");
require("packs/validation");
require("packs/badges");
require("packs/direct_uploads");
require("packs/discount_codes");
require("packs/effects");
require("packs/exam_responses");
require("packs/exams");
require("packs/forms");
require("packs/header");
require("packs/page_jumping");
require("packs/photo_gallery");
require("packs/print_orders");
require("packs/proficient_projects");
require("packs/questions");
require("packs/repositories");
require("packs/requests");
require("packs/settings");
require("packs/sorting");
require("packs/users");
require("packs/vendor");
require("packs/videos");
require("packs/volunteer_hours");
require("packs/volunteer_requests");
require("packs/volunteer_tasks");

import "bootstrap";
import "../stylesheets/application"
require("packs/toastr");

document.addEventListener("turbolinks:load", () => {
    $('[data-toggle="tooltip"]').tooltip()
    $('[data-toggle="popover"]').popover()
})

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

$(document).on('turbolinks:load', function () {

    var clipboard = new Clipboard('.clipboard-btn');
    console.log(clipboard);

});

