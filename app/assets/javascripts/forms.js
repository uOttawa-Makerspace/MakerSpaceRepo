var instructableFiles;
var photoFiles;
var categoryArray;
var equipmentArray;

$(document).on('page:load', function(){
  load();
});

$(document).on('ready', function(){
  load();
});

function load() {
  
  $('#redactor').redactor({
    minHeight: 100,
    buttons: ['formatting', 'bold', 'italic', 'deleted', 'unorderedlist', 'orderedlist', 'alignment', 'link', 'horizontalrule'],
    toolbarFixed: false
  });

  $('#comment-redactor').redactor({
    minHeight: 100,
    buttons: ['bold', 'italic', 'deleted', 'unorderedlist', 'orderedlist'],
    toolbarFixed: false
  });

  instructableFiles = [];
  photoFiles = [];
  categoryArray = [];
  equipmentArray = [];

  $('div#image-container').children().each(function(){
    var image_item = $(this);
    var close_button = $($(this).children()[0]);
    var image = image_item.children()[1];
    var canvas = convertImageToCanvas(image);
    var dataURL = canvas.toDataURL('image/jpeg', 0.5);
    var blob = dataURItoBlob(dataURL, image.dataset.name);
    photoFiles.push(blob);

    close_button.click(function(){
      var index = image_item.index();
      photoFiles.splice(index, 1);
      image_item.remove();
    });

  });
  
  var count=0;

  $('div#category-container').children().each(function(){
    
    //FIX - hack to make the select tag work properly
    if (count==0) {
      var x = document.getElementById("repository_categories");
      var option = document.createElement("option");
      option.text = "Select a category...";
      x.add(option, 0);
      x.value = "Select a category...";
      var y = document.getElementById("repository_equipments");
      var option2 = document.createElement("option");
      option2.text = "Select a piece of equipment...";
      y.add(option2, 0);
      y.value = "Select a piece of equipment...";
      document.getElementById("repository_license").value = "Creative Commons - Attribution";
      count++;
    }
    
    
    var cat_item = $(this);
    categoryArray.push(cat_item[0].innerText);

    $(cat_item).click(function(){
      var index = $(cat_item).index();
      categoryArray.splice(index, 1);
      $(cat_item).remove();
    });

  });
  
  $('div#equipment-container').children().each(function(){
    var equip_item = $(this);
    equipmentArray.push(equip_item[0].innerText);

    $(equip_item).click(function(){
      var index = $(equip_item).index();
      equipmentArray.splice(index, 1);
      $(equip_item).remove();
    });

  });
  

  dragndrop.call($("div#dragndrop"));

  $("input#user_avatar").change(function(){
    readURL(this);
  });

  $("input#images_").change(function(){
    var input = $(this)[0];
    if (input.files && input.files[0]) {
      var files = $.extend(true, [], input.files);
      addPhotos(photoFiles, files, 0);
    }
    resetFormElement(input);
  });

  $("input#files_").change(function(){
    var input = $(this)[0];
    if (input.files && input.files[0]) {
      var files = $.extend(true, [], input.files);
      addFiles(instructableFiles, files, 0);
    }
    resetFormElement(input);
  });
  
//Get categories
  $(document).ready(function() {
    $('#repository_categories').on('change', function(e) {
      var val = e.target.options[e.target.selectedIndex].value;
      e.target.selectedIndex = 0;
      if($("div#category-container").children().length === 5){
        return false;
      }
      for (var i=0; i<categoryArray.length; i++) {
        if (val==categoryArray[i]) {
          return false;
        }
      }
      e.preventDefault();
      categoryArray.push(val);
      $.get('/template/category', { 'category' : val }, function(data){
        $("div#category-container").append(data);
        var last = $("div#category-container")[0].children.length - 1;
        var child = $("div#category-container")[0].children[last];
        
        $(child).click(function(){
          var index = $(child).index();
          categoryArray.splice(index, 1);
          $(child).remove();
        });
        
      }, 'html');
    });
  });
  
  //Get pieces of equipment
  $(document).ready(function() {
    $('#repository_equipments').on('change', function(e) {
      var val = e.target.options[e.target.selectedIndex].value;
      e.target.selectedIndex = 0;
      if($("div#equipment-container").children().length === 5){
        return false;
      }
      for (var i=0; i<equipmentArray.length; i++) {
        if (val==equipmentArray[i]) {
          return false;
        }
      }
      e.preventDefault();
      equipmentArray.push(val);
      $.get('/template/equipment', { 'equipment' : val }, function(data){
        $("div#equipment-container").append(data);
        var last = $("div#equipment-container")[0].children.length - 1;
        var child = $("div#equipment-container")[0].children[last];
        
        $(child).click(function(){
          var index = $(child).index();
          equipmentArray.splice(index, 1);
          $(child).remove();
        });
        
      }, 'html');
    });
  });

  $("form#new_repository, form.edit_repository").submit(function(e){
    e.preventDefault();
    var validate = validation();

    var _this = $(this),
        uri   = _this[0].action,
        form  = new FormData(_this[0]);

    for (var i = 0; i < instructableFiles.length; i++) {
      form.append("files[]", instructableFiles[i]);
    };

    for (var i = 0; i < photoFiles.length; i++) {
      form.append("images[]", photoFiles[i]);
    };

    for (var i = 0; i < categoryArray.length; i++) {
      form.append("categories[]", categoryArray[i]);
    };
    
    for (var i = 0; i < equipmentArray.length; i++) {
      form.append("equipments[]", equipmentArray[i]);
    };

    if( validate ){ 
      $.ajax({
        url: uri,
        type: "POST",
        data: form,
        dataType: 'json',
        processData: false,
        contentType: false
      }).done(function(e) {
        window.location.pathname = e.redirect_uri 
      })
      .fail(function(e) {
        if( e.responseText === "not signed in" ){ window.location.href = '/login' }
        var span = $('<span>').addClass('form-error repo-form');
        span.text(e.responseText);
        $('input#repository_title').before(span); 
        console.log('error');
      });
    }
    
  });

}

function resetFormElement(e) {
  var el = $(e);
  el.wrap('<form>').closest('form').get(0).reset();
  el.unwrap();
}

function addFiles(fileArray, files, index){
  var file = files[index];
    fileArray.push(file);
    $.get('/template/file', { 'file' : file.name }, function(data){
      $("div#file-container").append(data);
      var last = $("div#file-container")[0].children.length - 1;
      var child = $("div#file-container")[0].children[last];

      $(child.children[1]).click(function(){
        var index = $(child).index();
        fileArray.splice(index, 1);
        $(child).remove();
      });

      if( files.length !== ++index){
        addFiles(fileArray, files, index);
      }
    }, 'html');
};

function addPhotos(fileArray, files, index){
  var file = files[index];
    if (file.type.match(/image.*/)){
      fileArray.push(file);
      var reader = new FileReader();
      reader.readAsDataURL(file);
      reader.onload = function (e) {
        loadImage(e.target.result, fileArray);
        if( files.length !== ++index){
          addPhotos(fileArray, files, index);
        }
      }
    }
};

function loadImage(image, fileArray){
  var image_item = $('<div>').addClass('image-item');
  var close_button = $('<span>').addClass('image-remove');
  var img = $('<img>').attr('src', image);
  image_item.append(img);
  image_item.append(close_button);
  $('div#image-container').append(image_item);

  close_button.click(function(){
    var index = image_item.index();
    fileArray.splice(index, 1);
    image_item.remove();
  });
}

function readURL(input) {
  if (input.files && input.files[0].type.match(/image.*/) ) {

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
    $('div.repo-image').css('border', '2px solid #0b85a1');
  });

  $(this).on('dragover', function(e){
    e.stopPropagation();
    e.preventDefault();
  });

  $(this).on('drop', function(e){
    $('div.repo-image').css('border', '1px dashed #aaa');
    e.preventDefault();

    var input = e.originalEvent.dataTransfer;
    if (input.files && input.files[0]) {
      var files = $.extend(true, [], input.files);
      addPhotos(photoFiles, files, 0);
    }
  });

}

 function directories(){
  var url = "/github/repositories.json";
  $.getJSON(url).done( function(data){ 
    setAutoComplete(data);
  });
}

function setAutoComplete(data){
  $("input.repo-autocomplete").autocomplete({
    position: { my : "left top+5", at: "left bottom" },
    source: data
  });
};

function convertImageToCanvas(image) {
  var canvas = document.createElement("canvas");
  canvas.width = image.dataset.width;
  canvas.height = image.dataset.height;
  canvas.getContext("2d").drawImage(image, 0, 0);
  return canvas;
}

function dataURItoBlob(dataURI, name) {
  var byteString = atob(dataURI.split(',')[1]);
  var ab = new ArrayBuffer(byteString.length);
  var ia = new Uint8Array(ab);
  for (var i = 0; i < byteString.length; i++) {
      ia[i] = byteString.charCodeAt(i);
  }
  return new File([ab], name, { type: 'image/jpeg' });
}