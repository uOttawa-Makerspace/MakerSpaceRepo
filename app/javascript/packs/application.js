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
require("jquery-ui")
require("justifiedGallery")
require("select2");
global.toastr = require("toastr");
global.Chart = require("chart.js");
require("trix");
require("@shopify/buy-button-js");
global.PhotoSwipe = require('photoswipe');
global.PhotoSwipeUI_Default = require('photoswipe/dist/photoswipe-ui-default');
var Clipboard = require("clipboard");
import moment from 'moment'
// window.Cookies = require("js-cookie");
require("@rails/actiontext")
require("flatpickr/dist/flatpickr")

require("bootbox");
require("packs/validation");
require("packs/direct_uploads");
require("packs/effects");
require("packs/forms");
require("packs/header");
require("packs/page_jumping");
require("packs/photo_gallery");
require("packs/requests");
require("packs/settings");
require("packs/sorting");
require("packs/vendor");
require("packs/accordion-load");

import "bootstrap";
import "tom-select";
require("packs/toastr");

import { Calendar } from '@fullcalendar/core';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import listPlugin from '@fullcalendar/list';

document.addEventListener("turbolinks:load", () => {
    $('[data-toggle="tooltip"]').tooltip()
    $('[data-toggle="popover"]').popover()

    const links = document.getElementsByTagName('a');

    for(let i=0;i<links.length;i++){
        const link = links[i];
        const href = link.getAttribute('href');
        if(href !== null && href.match(/^((https?:\/\/)|(www\.))/)) {
            link.setAttribute('target','_blank');
            link.setAttribute('rel', "noopener noreferrer")
        }
    }
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

window.clearEndDate = function() {
    document.getElementById("end_date").value = null;
}

window.setSpace = function(){
    let space_id = document.getElementById("set_space_id").value;

    $.ajax({
        url: "/staff_dashboard/change_space",
        type: "PUT",
        data: {
            space_id: space_id,
            training: document.URL.includes("training_sessions"),
            questions: document.URL.includes("questions"),
            shifts: document.URL.includes("shifts"),
        }
    })
}

window.debounce = function(func, wait, immediate) {
    let timeout;
    return function() {
        let context = this, args = arguments;
        let later = function() {
            timeout = null;
            if (!immediate) func.apply(context, args);
        };
        let callNow = immediate && !timeout;
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
        if (callNow) func.apply(context, args);
    };
};