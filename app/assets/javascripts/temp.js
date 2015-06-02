
// $(document).on('page:change', function(){ 

//   // directories();

//   $("select").selectmenu({
//     width: 422,
//     position: { my : "left top+5", at: "left bottom" }
//   });

//   // $("input#repository_title").blur(function(){
//   //   var content = $(this).val();
//   //   generateRepoDir(content);
//   // });
  

// });

// // function generateRepoDir(value){

// //   if(value == ""){ 
// //     $("section#dropbox-folders").slideUp(500);
// //     return; 
// //   }else if(this.lastLoaded == value){
// //     return;
// //   };
// //   $("section#dropbox-folders").slideUp(500);

// //   $("span.loader").fadeIn(300);
// //   var uri = "/dropbox/folders?path="+ value;

// //   $.ajax({ url: uri,
// //            dataType: "html"
// //   }).done( function(html){
// //       $("section#dropbox-folders").remove();
// //       $("input.repo").after(html);
// //       $("section#dropbox-folders").slideDown(500);
// //       $("span.loader").fadeOut(300);
// //     }).fail( function(){
// //       $("section#dropbox-folders").slideUp(500);
// //       $("span.loader").fadeOut(300);
// //     });

// //   this.lastLoaded = value;

// // }

// function readURL(input) {
//   if (input.files && input.files[0]) {
//     var reader = new FileReader();

//     reader.onload = function (e) {
//       $('img.edit-avatar').attr('src', e.target.result);
//     }
//     reader.readAsDataURL(input.files[0]);
//   }
// }

// // function directories(){
// //   var url = "/dropbox/folders.json?path=";
// //   $.getJSON(url).done( function(data){ 
// //     setAutoComplete(data);
// //   });
// // }

// // function setAutoComplete(data){
// //   $( "input#repository_title" ).autocomplete({
// //     position: { my : "left top+5", at: "left bottom" },
// //     source: dirArr(data),
// //     select: function(e, ui){ generateRepoDir(ui.item.value); }
// //   });
// // }

// // function dirArr(data){
// //   var keys = Object.keys(data);
// //   var dir = [];
// //   for(var key in data){
// //     if (data.hasOwnProperty(key) && data[key] == "directory") {
// //       dir.push(key);
// //     }
// //   }
// //   return dir;
// // }

// function readCookie(name) {
//     var nameEQ = name + "=";
//     var ca = document.cookie.split(';');
//     for(var i=0;i < ca.length;i++) {
//         var c = ca[i];
//         while (c.charAt(0)==' ') c = c.substring(1,c.length);
//         if (c.indexOf(nameEQ) == 0) return c.substring(nameEQ.length,c.length);
//     }
//     return null;
// }


