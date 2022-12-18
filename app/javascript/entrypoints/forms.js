// // function validation() {
// //     let ret = true;
// //     let title = $("input#repository_title");
// //     $('span.form-error.repo-form').remove();
// //     let span = $('<span>').addClass('form-error repo-form');
// //     let regex = /^[-a-zA-ZÀ-ÿ\d\s]*$/;
//
// //     if (title.val().length === 0) {
// //         span.text("Project title is required.");
// //         $('input#repository_title').before(span);
// //         ret = false;
// //     }
//
// //     if (!regex.test(title.val())) {
// //         span.text("Project title may only contain letters and numbers.");
// //         $('input#repository_title').before(span);
// //         ret = false;
// //     }
//
// //     let oldPhotosLength = document.querySelectorAll("#image-container > div").length;
//
// //     span = $('<span>').addClass('form-error repo-form');
//
// //     if ((photoFiles.length === 0) && (oldPhotosLength == 0)) {
// //         span.text("At least one photo is required.");
// //         $('div.repo-image').before(span);
// //         ret = false;
// //     }
//
// //     span = $('<span>').addClass('form-error repo-form');
//
// //     // if( categoryArray.length === 0 ){
// //     // 	span.text("At least one category is required.");
// //     // 	$('select#repository_categories').before(span);
// //     // 	ret = false;
// //     // }
//
// //     return ret;
// // }
//
// // function validation_proposal() {
// //     let title = $("input#project_proposal_title");
// //     let name = $("input#project_proposal_username");
// //     let email = $("input#project_proposal_email");
// //     let client = $("input#project_proposal_client");
// //     let client_background = $("input#project_proposal_client_background");
// //     let description = $("#project_proposal_description");
// //     $('span.form-error.repo-form').remove();
// //     let span = $('<span>').addClass('form-error repo-form');
// //     let regex = /^[-a-zA-ZÀ-ÿ\d\s]*$/;
//
// //     if (name.val().length === 0) {
// //         span.text("Your name is required");
// //         $('input#project_proposal_username').before(span);
// //         scrow_to_error("project_proposal_username");
// //         return false;
// //     }
//
// //     if (email.val().length === 0) {
// //         span.text("Your email is required");
// //         $('input#project_proposal_email').before(span);
// //         scrow_to_error("project_proposal_email");
// //         return false;
// //     }
//
// //     if (client.val().length === 0) {
// //         span.text("Client is required");
// //         $('input#project_proposal_client').before(span);
// //         scrow_to_error("project_proposal_client");
// //         return false;
// //     }
//
// //     if (title.val().length === 0) {
// //         span.text("Project title is required.");
// //         $('input#project_proposal_title').before(span);
// //         scrow_to_error("project_proposal_title");
// //         return false;
// //     }
//
// //     if (!regex.test(title.val())) {
// //         span.text("Project title may only contain letters and numbers.");
// //         $('input#project_proposal_title').before(span);
// //         scrow_to_error("project_proposal_title");
// //         return false;
// //     }
//
// //     if (client_background.val().length === 0) {
// //         span.text("Client background is required.");
// //         $('input#project_proposal_client_background').before(span);
// //         scrow_to_error("project_proposal_client_background");
// //         return false;
// //     }
//
// //     if (description.val().length === 0) {
// //         span.text("Description is required.");
// //         $('#project_proposal_description').before(span);
// //         scrow_to_error("project_proposal_description");
// //         return false;
// //     }
// //     return true
// // }
//
// // function scrow_to_error(element_id) {
// //     let elmnt = document.getElementById(element_id);
// //     elmnt.scrollIntoView(true);
// //     const scrolledY = window.scrollY;
// //     if (scrolledY) {
// //         window.scroll(0, scrolledY - 170);
// //     }
// // }
//
// // let instructableFiles;
// // let videoFiles;
// // let photoFiles;
// // let categoryArray;
// // let equipmentArray;
// // let certificationArray;
//
// // $(document).on("turbolinks:load", function () {
//
// //     $('body').on('click', 'button.link-list', function () {
// //         let id = $('.main_ul')[0].childElementCount - 1;
// //         $('.main_ul').append(
// //             $('<li><div class="mb-3"><input  placeholder="Ajoutez un lien / Add a link" class="link_name form-control" type="text"></div></li>')
// //         );
// //     });
//
// //     $('body').on('click', 'button#remove-link-list', function () {
// //         let id = $('.main_ul')[0].childElementCount - 1;
// //         $('.main_ul')[0].removeChild($('.main_ul')[0].childNodes[id]);
// //     });
//
// //     load();
// // });
//
// // function load() {
//
// //     $('#select-all').click(function (event) {
// //         if (this.checked) {
// //             $(':checkbox').each(function () {
// //                 this.checked = true;
// //             });
// //         } else {
// //             $(':checkbox').each(function () {
// //                 this.checked = false;
// //             });
// //         }
// //     });
//
// //     //**************** START | download zip stuff *******************//
//
// //     let setCookie = function (name, value, expiracy) {
// //         let exdate = new Date();
// //         exdate.setTime(exdate.getTime() + expiracy * 1000);
// //         let c_value = escape(value) + ((expiracy == null) ? "" : "; expires=" + exdate.toUTCString());
// //         document.cookie = name + "=" + c_value + '; path=/';
// //     };
//
// //     let getCookie = function (name) {
// //         let i, x, y, ARRcookies = document.cookie.split(";");
// //         for (i = 0; i < ARRcookies.length; i++) {
// //             x = ARRcookies[i].substr(0, ARRcookies[i].indexOf("="));
// //             y = ARRcookies[i].substr(ARRcookies[i].indexOf("=") + 1);
// //             x = x.replace(/^\s+|\s+$/g, "");
// //             if (x == name) {
// //                 return y ? decodeURI(unescape(y.replace(/\+/g, ' '))) : y; //;//unescape(decodeURI(y));
// //             }
// //         }
// //     };
//
// //     $('#download-zip').click(function (event) {
// //         $("#download-zip").attr('class', 'no-bg-download');
// //         $("#download-zip").html("<img src='/assets/loader-65526d2bb686aee87b0257dcbc756449cffeebf62d6646ba9a9979de8b51111a.gif' height='15px'>");
// //         setCookie('downloadStarted', 0, 100);
// //         setTimeout(checkDownloadCookie, 1000);
// //         window.location = location.href + "/download_files";
// //         event.preventDefault();
// //     });
//
// //     let downloadTimeout;
// //     let checkDownloadCookie = function () {
// //         if (getCookie("downloadStarted") == 1) {
// //             setCookie("downloadStarted", "false", 100);
// //             $("#download-zip").attr('class', 'bg-download');
// //             $("#download-zip").html("<i class=\"fa fa-download\"></i> Download");
// //         } else {
// //             downloadTimeout = setTimeout(checkDownloadCookie, 1000);
// //         }
// //     };
//
// //     //**************** END | download zip stuff *******************//
//
// //     instructableFiles = [];
// //     videoFiles = [];
// //     photoFiles = [];
// //     categoryArray = [];
// //     equipmentArray = [];
// //     certificationArray = [];
//
// //     $('div#image-container').children().each(function () {
// //         let image_item = $(this);
// //         let close_button = $($(this).children()[0]);
//
// //         close_button.click(function (e) {
// //             let index = $(image_item).index();
// //             photoFiles.splice(index, 1);
// //             document.getElementById("deleteimages").value = document.getElementById("deleteimages").value + e.target.id + ",";
// //             image_item.remove();
// //         });
//
// //     });
//
// //     dragndrop.call($("div#dragndrop"));
//
// //     $("input#user_avatar").change(function () {
// //         readURL(this);
// //     });
//
// //     $("input#images_").change(function () {
// //         let input = $(this)[0];
// //         if (input.files && input.files[0]) {
// //             let files = $.extend(true, [], input.files);
// //             addPhotos(photoFiles, files, 0);
// //         }
// //         resetFormElement(input);
// //     });
//
// //     $("input#files_").change(function () {
// //         let input = $(this)[0];
// //         if (input.files && input.files[0]) {
// //             let files = $.extend(true, [], input.files);
// //             addFiles(instructableFiles, files, 0);
// //         }
// //         resetFormElement(input);
// //     });
//
// //     $("input#videos_").change(function () {
// //         let input = $(this)[0];
// //         if (input.files && input.files[0]) {
// //             let files = $.extend(true, [], input.files);
// //             addVideos(videoFiles, files, 0);
// //         }
// //         resetFormElement(input);
// //     });
//
// //     //CATEGORY-EQUIPMENT-CERTIFICATION STUFF (START)
// //     // edit page
// //     $('div#category-container').children().each(function () {
// //         let cat_item = $(this);
// //         let x = document.querySelector("#repository_categories, #project_proposal_categories");
// //         let id = x.id
//
// //         for (let i = 0; i < x.options.length; i++) {
// //             if (x.options[i].childNodes[0].nodeValue === cat_item[0].childNodes[0].nodeValue) {
// //                 x.remove(i);
// //             }
// //         }
// //         categoryArray.push(cat_item[0].innerText);
//
// //         $(cat_item).click(function () {
// //             let option = document.createElement("option");
// //             option.text = cat_item[0].innerText;
// //             x.add(option);
// //             sort_options(id);
// //             let index = $(cat_item).index();
// //             categoryArray.splice(index, 1);
// //             $(cat_item).remove();
// //         });
//
// //     });
// if (document.getElementById("equipment-container")) {
//   document
//     .getElementById("equipment_container")
//     .children()
//     .each(function (e) {
//       console.log(e);
//     });
// }
// $("div#equipment-container")
//   .children()
//   .each(function () {
//     let equip_item = $(this);
//     let x = document.getElementById("repository_equipments");
//
//     for (let i = 0; i < x.options.length; i++) {
//       if (
//         x.options[i].childNodes[0].nodeValue ===
//         equip_item[0].childNodes[0].nodeValue
//       ) {
//         x.remove(i);
//       }
//     }
//     equipmentArray.push(equip_item[0].innerText);
//
//     $(equip_item).click(function () {
//       let option = document.createElement("option");
//       option.text = equip_item[0].innerText;
//       x.add(option);
//       sort_options("repository_equipments");
//       let index = $(equip_item).index();
//       equipmentArray.splice(index, 1);
//       $(equip_item).remove();
//     });
//   });
//
// //     $('div#certification-container').children().each(function () {
// //         let certif_item = $(this);
// //         let x = document.getElementById("user_certifications");
//
// //         for (let i = 0; i < x.options.length; i++) {
// //             if (x.options[i].childNodes[0].nodeValue === certif_item[0].childNodes[0].nodeValue) {
// //                 x.remove(i);
// //             }
// //         }
// //         certificationArray.push(certif_item[0].innerText);
//
// //         $(certif_item).click(function () {
// //             let option = document.createElement("option");
// //             option.text = certif_item[0].innerText;
// //             x.add(option);
// //             sort_options("user_certifications");
// //             let index = $(certif_item).index();
// //             certificationArray.splice(index, 1);
// //             $(certif_item).remove();
// //         });
//
// //     });
//
// //     //TODO: make a function to get any object
// // //Get categories
// //     $(document).ready(function () {
// //         $('#repository_categories').on('change', function (e) {
// //             let val = e.target.options[e.target.selectedIndex].text;
// //             e.target.remove(e.target.selectedIndex);
// //             e.target.selectedIndex = 0;
// //             if ($("div#category-container").children().length === 5) {
// //                 return false;
// //             }
// //             for (let i = 0; i < categoryArray.length; i++) {
// //                 if (val == categoryArray[i]) {
// //                     return false;
// //                 }
// //             }
// //             e.preventDefault();
// //             categoryArray.push(val);
// //             $.get('/template/category', {'category': val}, function (data) {
// //                 $("div#category-container").append(data);
// //                 let last = $("div#category-container")[0].children.length - 1;
// //                 let child = $("div#category-container")[0].children[last];
//
// //                 $(child).click(function () {
// //                     let index = $(child).index();
// //                     let option = document.createElement("option");
// //                     option.text = categoryArray[index];
// //                     document.getElementById("repository_categories").add(option);
// //                     sort_options("repository_categories");
// //                     categoryArray.splice(index, 1);
// //                     $(child).remove();
// //                 });
//
// //             }, 'html');
// //         });
// //     });
//
// //     //Get categories for project proposals
// //     $(document).ready(function () {
// //         $('#project_proposal_categories').on('change', function (e) {
// //             let val = e.target.options[e.target.selectedIndex].text;
// //             e.target.remove(e.target.selectedIndex);
// //             e.target.selectedIndex = 0;
// //             if ($("div#category-container").children().length === 5) {
// //                 return false;
// //             }
// //             for (let i = 0; i < categoryArray.length; i++) {
// //                 if (val == categoryArray[i]) {
// //                     return false;
// //                 }
// //             }
// //             e.preventDefault();
// //             categoryArray.push(val);
// //             $.get('/template/category', {'category': val}, function (data) {
// //                 $("div#category-container").append(data);
// //                 let last = $("div#category-container")[0].children.length - 1;
// //                 let child = $("div#category-container")[0].children[last];
//
// //                 $(child).click(function () {
// //                     let index = $(child).index();
// //                     let option = document.createElement("option");
// //                     option.text = categoryArray[index];
// //                     document.getElementById("project_proposal_categories").add(option);
// //                     sort_options("project_proposal_categories");
// //                     categoryArray.splice(index, 1);
// //                     $(child).remove();
// //                 });
//
// //             }, 'html');
// //         });
// //     });
//
// //     //Get pieces of equipment
// //     $(document).ready(function () {
// //         $('#repository_equipments').on('change', function (e) {
// //             let val = e.target.options[e.target.selectedIndex].text;
// //             e.target.remove(e.target.selectedIndex);
// //             e.target.selectedIndex = 0;
// //             if ($("div#equipment-container").children().length === 5) {
// //                 return false;
// //             }
// //             for (let i = 0; i < equipmentArray.length; i++) {
// //                 if (val == equipmentArray[i]) {
// //                     return false;
// //                 }
// //             }
// //             e.preventDefault();
// //             equipmentArray.push(val);
// //             $.get('/template/equipment', {'equipment': val}, function (data) {
// //                 $("div#equipment-container").append(data);
// //                 let last = $("div#equipment-container")[0].children.length - 1;
// //                 let child = $("div#equipment-container")[0].children[last];
//
// //                 $(child).click(function () {
// //                     let index = $(child).index();
// //                     let option = document.createElement("option");
// //                     option.text = equipmentArray[index];
// //                     document.getElementById("repository_equipments").add(option);
// //                     sort_options("repository_equipments");
// //                     equipmentArray.splice(index, 1);
// //                     $(child).remove();
// //                 });
//
// //             }, 'html');
// //         });
// //     });
//
// //     //Get certifications
// //     $(document).ready(function () {
// //         $('#user_certifications').on('change', function (e) {
// //             let val = e.target.options[e.target.selectedIndex].text;
// //             e.target.remove(e.target.selectedIndex);
// //             e.target.selectedIndex = 0;
//
// //             for (let i = 0; i < certificationArray.length; i++) {
// //                 if (val == certificationArray[i]) {
// //                     return false;
// //                 }
// //             }
//
// //             e.preventDefault();
// //             certificationArray.push(val);
// //             $.get('/template/certification', {'certification': val}, function (data) {
// //                 $("div#certification-container").append(data);
// //                 let last = $("div#certification-container")[0].children.length - 1;
// //                 let child = $("div#certification-container")[0].children[last];
//
// //                 $(child).click(function () {
// //                     let index = $(child).index();
// //                     let option = document.createElement("option");
// //                     option.text = certificationArray[index];
// //                     document.getElementById("user_certifications").add(option);
// //                     sort_options("user_certifications");
// //                     certificationArray.splice(index, 1);
// //                     $(child).remove();
//
// //                 });
// //             }, 'html');
// //         });
// //     });
//
// //     //CATEGORY-EQUIPMENT-CERTIFICATION STUFF (END)
//
// //     $("form.edit_admin_user").submit(function (e) {
// //         e.preventDefault();
//
// //         let _this = $(this),
// //             uri = _this[0].action,
// //             form = new FormData(_this[0]);
//
// //         for (let i = 0; i < certificationArray.length; i++) {
// //             form.append("certifications[]", certificationArray[i]);
// //         }
// //         ;
//
// //         $.ajax({
// //             url: uri,
// //             type: "POST",
// //             data: form,
// //             dataType: 'json',
// //             processData: false,
// //             contentType: false
// //         }).done(function (e) {
// //             window.location.pathname = e.redirect_uri
// //         })
// //             .fail(function (e) {
// //                 if (e.responseText === "not signed in") {
// //                     window.location.href = '/login'
// //                 }
// //                 let span = $('<span>').addClass('form-error repo-form');
// //                 span.text(e.responseText);
// //                 $('input#repository_title').before(span);
// //                 console.log('error');
// //             });
//
// //     });
//
// //     $("form#new_repository, form.edit_repository, form#new_proficient_project, form.edit_proficient_project, form#new_learning_module, form.edit_learning_module, form.makes_new").submit(function (e) {
// //         e.preventDefault();
//
// //         console.log(categoryArray.length);
//
// //         let validate = validation();
//
// //         $("#form-error-span").text("");
//
// //         let _this = $(this),
// //             uri = _this[0].action,
// //             form = new FormData(_this[0]);
//
// //         for (let i = 0; i < instructableFiles.length; i++) {
// //             form.append("files[]", instructableFiles[i]);
// //         }
//
// //         for (let i = 0; i < videoFiles.length; i++) {
// //             form.append("videos[]", videoFiles[i]);
// //         }
//
// //         for (let i = 0; i < photoFiles.length; i++) {
// //             form.append("images[]", photoFiles[i]);
// //         }
//
// //         for (let i = 0; i < categoryArray.length; i++) {
// //             form.append("categories[]", categoryArray[i]);
// //         }
//
// //         for (let i = 0; i < equipmentArray.length; i++) {
// //             form.append("equipments[]", equipmentArray[i]);
// //         }
//
// //         if (validate) {
// //             document.getElementById("status-save").innerHTML = "<img src='/assets/loader-65526d2bb686aee87b0257dcbc756449cffeebf62d6646ba9a9979de8b51111a.gif' height='15px'> Saving project...";
// //             $.ajax({
// //                 url: uri,
// //                 type: "POST",
// //                 data: form,
// //                 dataType: 'json',
// //                 processData: false,
// //                 contentType: false
// //             }).done(function (e) {
// //                 window.location.pathname = e.redirect_uri
// //             })
// //                 .fail(function (e) {
// //                     if (e.responseText === "not signed in") {
// //                         window.location.href = '/login'
// //                     }
// //                     let span = $('<span>').addClass('form-error repo-form');
// //                     span.text(e.responseText);
// //                     $('input#repository_title').before(span);
// //                     console.log('error');
// //                 });
// //         } else {
// //             $("#waiting-save-button").attr('disabled', 'true');
// //             $("#form-error-span").text("Please check all the errors in the form and try again !").addClass('form-error repo-form');
// //             setTimeout(() => {
// //                 $("#waiting-save-button").removeAttr('data-disable-with').removeAttr('disabled');
// //             }, 1000);
// //         }
//
// //     });
//
// //     $("form#new_project_proposal, form.edit_project_proposal").submit(function (e) {
//
// //         let experiences_list = "";
//
// //         Array.from(document.getElementsByClassName("link_name")).forEach(
// //             function (element, index, array) {
// //                 experiences_list += element.value + ",";
// //             }
// //         );
// //         if (experiences_list.length >= 1) {
// //             experiences_list = experiences_list.substring(0, experiences_list.length - 1);
// //         }
//
// //         document.getElementById('project_proposal_past_experiences').value += "|" + "" + experiences_list;
//
// //         e.preventDefault();
//
// //         let validate = validation_proposal();
//
// //         let _this = $(this),
// //             uri = _this[0].action,
// //             form = new FormData(_this[0]);
//
// //         for (let i = 0; i < instructableFiles.length; i++) {
// //             form.append("files[]", instructableFiles[i]);
// //         }
//
// //         for (let i = 0; i < photoFiles.length; i++) {
// //             form.append("images[]", photoFiles[i]);
// //         }
//
// //         for (let i = 0; i < categoryArray.length; i++) {
// //             form.append("categories[]", categoryArray[i]);
// //         }
//
// //         if (validate) {
// //             document.getElementById("status-save").innerHTML = "<img src='/assets/loader-65526d2bb686aee87b0257dcbc756449cffeebf62d6646ba9a9979de8b51111a.gif' height='15px'> Saving project...";
// //             $.ajax({
// //                 url: uri,
// //                 type: "POST",
// //                 data: form,
// //                 dataType: 'json',
// //                 processData: false,
// //                 contentType: false
// //             }).done(function (e) {
// //                 window.location.href = e.redirect_uri
// //             })
// //                 .fail(function (e) {
// //                     if (e.responseText === "not signed in") {
// //                         window.location.href = '/login'
// //                     }
// //                     let span = $('<span>').addClass('form-error repo-form');
// //                     span.text(e.responseText);
// //                     $('input#repository_title').before(span);
// //                     console.log('error');
// //                 });
// //         } else {
// //             //TODO: jQuery(window).scrollTop(jQuery('[class$="form-error"]:first').position().top);
// //         }
//
// //     });
//
// //     $("span.file-remove").click(function (e) {
// //         let index = $($(this)).index();
// //         instructableFiles.splice(index, 1);
// //         console.log(document.getElementById("deletefiles").value + e.target.id + ",")
// //         document.getElementById("deletefiles").value = document.getElementById("deletefiles").value + e.target.id + ",";
// //         e.target.parentElement.parentElement.parentElement.remove();
// //     });
//
// //     $('div#video-container').children().each(function () {
// //         let file_item = $(this);
//
// //         $("span.video-remove").click(function (e) {
// //             let index = $(file_item).index();
// //             videoFiles.splice(index, 1);
// //             document.getElementById("deletevideos").value = document.getElementById("deletevideos").value + e.target.id + ",";
// //             e.target.parentElement.parentElement.parentElement.remove();
// //         });
//
// //     });
//
// // }
//
// // function resetFormElement(e) {
// //     let el = $(e);
// //     el.wrap('<form>').closest('form').get(0).reset();
// //     el.unwrap();
// // }
//
// // function addFiles(fileArray, files, index) {
// //     let file = files[index];
// //     if (true) {
// //         fileArray.push(file);
// //         let reader = new FileReader();
// //         reader.readAsDataURL(file);
// //         reader.onload = function (e) {
// //             loadFile(file.name, Math.round(file.size / 1000), fileArray);
// //             if (files.length !== ++index) {
// //                 addFiles(fileArray, files, index);
// //             }
// //         }
// //     }
// // }
//
// // function loadFile(filename, filesize, fileArray) {
// //     let file_item = $('<div>').addClass('file-item');
// //     let close_button = $('<span>').addClass('file-remove');
// //     let span = $('<span>').textContent = filename;
// //     file_item.append(span);
// //     file_item.append(close_button);
// //     $.get('/template/file', {'file': filename, 'size': filesize}, function (file_item) {
// //         $('div#file-container').append(file_item);
// //         let last = $("div#file-container")[0].children.length - 1;
// //         let child = $("div#file-container")[0].children[last];
//
// //         $(child.children[0].children[0].children[2].children[0]).click(function () {
// //             let length = document.querySelectorAll("#file-container > table").length;
// //             let index = $(child).index();
// //             fileArray.splice(index - length, 1);
// //             $(child).remove();
// //         });
// //     }, 'html');
// // }
//
// // function addVideos(fileArray, files, index) {
// //     let file = files[index];
// //     if (true) {
// //         fileArray.push(file);
// //         let reader = new FileReader();
// //         reader.readAsDataURL(file);
// //         reader.onload = function (e) {
// //             loadVideo(file.name, Math.round(file.size / 1000), fileArray);
// //             if (files.length !== ++index) {
// //                 addVideos(fileArray, files, index);
// //             }
// //         }
// //     }
// // }
//
// // function loadVideo(filename, filesize, fileArray) {
// //     let file_item = $('<div>').addClass('file-item');
// //     let close_button = $('<span>').addClass('file-remove');
// //     let span = $('<span>').textContent = filename;
// //     file_item.append(span);
// //     file_item.append(close_button);
// //     $.get('/template/file', {'file': filename, 'size': filesize}, function (file_item) {
// //         $('div#video-container').append(file_item);
// //         let last = $("div#video-container")[0].children.length - 1;
// //         let child = $("div#video-container")[0].children[last];
//
// //         $(child.children[0].children[0].children[2].children[0]).click(function () {
// //             let length = document.querySelectorAll("#video-container > table").length;
// //             let index = $(child).index();
// //             fileArray.splice(index - length, 1);
// //             $(child).remove();
// //         });
// //     }, 'html');
// // }
//
// // function addPhotos(fileArray, files, index) {
// //     let file = files[index];
// //     if (file.type.match(/image.*/)) {
// //         fileArray.push(file);
// //         let reader = new FileReader();
// //         reader.readAsDataURL(file);
// //         reader.onload = function (e) {
// //             loadImage(e.target.result, fileArray);
// //             if (files.length !== ++index) {
// //                 addPhotos(fileArray, files, index);
// //             }
// //         }
// //     }
// // }
//
// // function loadImage(image, fileArray) {
// //     let image_item = $('<div>').addClass('image-item');
// //     let close_button = $('<span>').addClass('image-remove');
// //     let img = $('<img>').attr('src', image);
// //     image_item.append(img);
// //     image_item.append(close_button);
// //     $('div#image-container').append(image_item);
//
// //     close_button.click(function () {
// //         let length = document.querySelectorAll("#image-container > div").length;
// //         let index = image_item.index();
// //         fileArray.splice(index - length, 1);
// //         image_item.remove();
// //     });
// // }
//
// // function readURL(input) {
// //     if (input.files && input.files[0].type.match(/image.*/)) {
//
// //         let reader = new FileReader();
// //         reader.readAsDataURL(input.files[0]);
//
// //         reader.onload = function (e) {
// //             $('img.edit-avatar').attr('src', e.target.result);
//
// //         }
// //     }
// // }
//
// // function dragndrop() {
// //     $(this).on('dragenter', function (e) {
// //         e.stopPropagation();
// //         e.preventDefault();
// //         $('div.repo-image').css('border', '2px solid #0b85a1');
// //     });
//
// //     $(this).on('dragover', function (e) {
// //         e.stopPropagation();
// //         e.preventDefault();
// //     });
//
// //     $(this).on('drop', function (e) {
// //         $('div.repo-image').css('border', '1px dashed #aaa');
// //         e.preventDefault();
//
// //         let input = e.originalEvent.dataTransfer;
// //         if (input.files && input.files[0]) {
// //             let files = $.extend(true, [], input.files);
// //             addPhotos(photoFiles, files, 0);
// //         }
// //     });
//
// // }
//
// // function setAutoComplete(data) {
// //     $("input.repo-autocomplete").autocomplete({
// //         position: {my: "left top+5", at: "left bottom"},
// //         source: data
// //     });
// // };
//
// // // To delete the category from edit or new
// // function sort_options(id) {
// //     $("#" + id).html($("#" + id + " option").sort(function (a, b) {
// //         if (!(a.text.includes("Select")) && !(b.text.includes("Select"))) {
// //             return a.text.toLowerCase() == b.text.toLowerCase() ? 0 : a.text.toLowerCase() < b.text.toLowerCase() ? -1 : 1
// //         }
// //     }));
// //     document.getElementById(id).selectedIndex = 0;
// // }
