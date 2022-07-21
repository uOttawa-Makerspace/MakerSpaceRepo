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
// require("jquery");
// require("jquery-ui")
global.toastr = require("toastr");
global.Chart = require("chart.js");
require("trix");
require("@shopify/buy-button-js");
global.PhotoSwipe = require('photoswipe');
global.TomSelect = require("tom-select");
global.PhotoSwipeUI_Default = require('photoswipe/dist/photoswipe-ui-default');
import "clipboard";
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
require("packs/clipboard");
//Shouldn't be necessary, remove when controllers load properly.


window.bootstrap = require('bootstrap/dist/js/bootstrap.bundle.js');
window.TomSelect = require("tom-select");
import "bootstrap";
import bsCustomFileInput from 'bs-custom-file-input'
require("packs/toastr");


import { Calendar } from '@fullcalendar/core';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import listPlugin from '@fullcalendar/list';

document.addEventListener("turbolinks:load", () => {
    let tooltips = document.querySelectorAll("[data-bs-toggle=\"tooltip\"]")
    tooltips.forEach(tooltip => {
        return new bootstrap.Tooltip(tooltip)
    });
    let popovers = document.querySelectorAll("[data-bs-toggle=\"popover\"]")
    popovers.forEach(popover => {
        return new bootstrap.Popover(popover)
    });

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

// // needed since by default form-select doesn't register page:load events
// document.addEventListener("turbolinks:load", () => {
//     $('[data-radio-enable]').on('change', function () {
//         var $inputs = $('input[type="radio"][name="' + $(this).attr('name') + '"]');

//         $inputs.each(function () {
//             var $input = $(this);
//             var $target = $($input.data('radio-enable'));

//             if ($input.prop('checked')){
//                 $target.prop('disabled', false);
//             } else {
//                 $target.prop('disabled', true);
//             }
//         });
//     }).trigger('change');

//     $('.form-select').selectpicker({
//         windowPadding: [80, 0, 0, 0]
//     });
// });


window.clearEndDate = function() {
    document.getElementById("end_date").value = null;
}

window.setSpace = function(){
    let space_id = document.getElementById("set_space_id").value;
    let url = "/staff_dashboard/change_space";
    fetch(url, {
        method: "PUT",
        credentials: 'include',
        headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        body:JSON.stringify({
            space_id: space_id,
            training: document.URL.includes("training_sessions"),
            questions: document.URL.includes("questions"),
            shifts: document.URL.includes("shifts"),
        }),
    }).then(response => response.json()).then(data => {
        Turbolinks.clearCache()
        Turbolinks.visit(window.location, {"action":"replace"})
    }).catch(error => {console.log(error)})
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
window.examResponse = function(exam_id, answer_id){
    fetch('/exam_responses#create', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            exam_id: exam_id,
            answer_id: answer_id
        })
    })
}
