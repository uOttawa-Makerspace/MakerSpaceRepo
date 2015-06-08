
$(document).on('page:change', function(){ 

  directories();
  dragndrop.call($("div#dragndrop"));
  // photoGal();
  $("select").selectmenu({
    width: 422,
    position: { my : "left top+5", at: "left bottom" }
  });

$("input#user_avatar").change(function(){
    readURL(this);
  });

$("input#repository_photos_attributes_0_image").change(function(){
    readURLs(this);
  });

});

function photoGal(){
  var pswpElement = document.querySelectorAll('.pswp')[0];
  var options = { index : 0 };
  var items = [{
    src: 'https://placekitten.com/600/400',
        w: 600,
        h: 400
  }];
  var gallery = new PhotoSwipe( pswpElement, PhotoSwipeUI_Default, items, options);
  gallery.init();
}


function readURL(input) {
  if (input.files && input.files[0]) {
    var reader = new FileReader();
    reader.readAsDataURL(input.files[0]);

    reader.onload = function (e) {
      $('img.edit-avatar').attr('src', e.target.result);

    }
  }
}

function dragndrop(){
  $(this).on('dragenter', function(e){
    e.stopPropagation();
    e.preventDefault();
    $('div.repo-image').css('border', '2px solid #0B85A1');
  });

  $(this).on('dragover', function(e){
    e.stopPropagation();
    e.preventDefault();
  });

  $(this).on('drop', function(e){
    $('div.repo-image').css('border', '1px dashed #aaa');
    e.preventDefault();
    readURLs(e.originalEvent.dataTransfer);
  });

}

function readURLs(input){
  if (input.files && input.files[0]) {
    $('span.image-item img').hide();
    for (var i = 0; i < input.files.length; i++) {
      var reader = new FileReader();
      reader.readAsDataURL(input.files[i]);
      reader.onload = function (e) {
        loadImage(e.target.result);
      }
    }
  }
}

function loadImage(image){
  var index = ["img.one", "img.two", "img.three", "img.four", "img.five", "img.six"];

  for (var i = 0; i < index.length; i++) {
    if($(index[i]).is(':hidden')){
      $(index[i]).attr('src', image);
      $(index[i]).fadeIn(500); 
      break;   
    }
  };
}

function directories(){
  var url = "/github/repositories.json";
  $.getJSON(url).done( function(data){ 
    setAutoComplete(data);
  });
}

function setAutoComplete(data){
  $( "input#repository_github" ).autocomplete({
    position: { my : "left top+5", at: "left bottom" },
    source: Object.keys(data),
  });
}
