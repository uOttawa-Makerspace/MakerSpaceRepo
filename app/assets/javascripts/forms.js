var instructableFiles;
var photoFiles;
var categoryArray;
var equipmentArray;
var certificationArray;

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
  
  $('#select-all').click(function(event) {   
    if(this.checked) {
        $(':checkbox').each(function() {
            this.checked = true;                        
        });
    }
    else {
        $(':checkbox').each(function() {
            this.checked = false;
        });
    }
  });

  instructableFiles = [];
  photoFiles = [];
  categoryArray = [];
  equipmentArray = [];
  certificationArray = [];

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
  
  //CATEGORY-EQUIPMENT-CERTIFICATION STUFF (START)
  
  $('div#category-container').children().each(function(){
    var cat_item = $(this);
    var x = document.getElementById("repository_categories");
    
    for (var i=0; i<x.options.length;i++) {
        if (x.options[i].childNodes[0].nodeValue === cat_item[0].childNodes[0].nodeValue){
            x.remove(i);
        }
    }
    categoryArray.push(cat_item[0].innerText);

    $(cat_item).click(function(){
      var option = document.createElement("option");
      option.text = cat_item[0].innerText;
      x.add(option);
      sort_options("repository_categories");
      var index = $(cat_item).index();
      categoryArray.splice(index, 1);
      $(cat_item).remove();
    });

  });
  
  $('div#equipment-container').children().each(function(){
    var equip_item = $(this);
    var x = document.getElementById("repository_equipments");
    
    for (var i=0; i<x.options.length;i++) {
        if (x.options[i].childNodes[0].nodeValue === equip_item[0].childNodes[0].nodeValue){
            x.remove(i);
        }
    }
    equipmentArray.push(equip_item[0].innerText);

    $(equip_item).click(function(){
      var option = document.createElement("option");
      option.text = equip_item[0].innerText;
      x.add(option);
      sort_options("repository_equipments");
      var index = $(equip_item).index();
      equipmentArray.splice(index, 1);
      $(equip_item).remove();
    });

  });
  
  $('div#certification-container').children().each(function(){
    var certif_item = $(this);
    var x = document.getElementById("user_certifications");
    
    for (var i=0; i<x.options.length;i++) {
        if (x.options[i].childNodes[0].nodeValue === certif_item[0].childNodes[0].nodeValue){
            x.remove(i);
        }
    }
    certificationArray.push(certif_item[0].innerText);
    
    

    $(certif_item).click(function(){
      var option = document.createElement("option");
      option.text = certif_item[0].innerText;
      x.add(option);
      sort_options("user_certifications");
      var index = $(certif_item).index();
      certificationArray.splice(index, 1);
      $(certif_item).remove();
    });

  });
  
  
  
//Get categories
  $(document).ready(function() {
    $('#repository_categories').on('change', function(e) {
      var val = e.target.options[e.target.selectedIndex].text;
      e.target.remove(e.target.selectedIndex);
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
          var option = document.createElement("option");
          option.text = categoryArray[index];
          document.getElementById("repository_categories").add(option);
          sort_options("repository_categories");
          categoryArray.splice(index, 1);
          $(child).remove();
        });
        
      }, 'html');
    });
  });
  
  //Get pieces of equipment
  $(document).ready(function() {
    $('#repository_equipments').on('change', function(e) {
      var val = e.target.options[e.target.selectedIndex].text;
      e.target.remove(e.target.selectedIndex);
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
          var option = document.createElement("option");
          option.text = equipmentArray[index];
          document.getElementById("repository_equipments").add(option);
          sort_options("repository_equipments");
          equipmentArray.splice(index, 1);
          $(child).remove();
        });
        
      }, 'html');
    });
  });
  
  
  
  //Get certifications
  $(document).ready(function() {
    $('#user_certifications').on('change', function(e) {
      var val = e.target.options[e.target.selectedIndex].text;
      e.target.remove(e.target.selectedIndex);
      e.target.selectedIndex = 0;
      
      
      for (var i=0; i<certificationArray.length; i++) {
        if (val==certificationArray[i]) {
          return false;
        }
      }
      
      e.preventDefault();
      certificationArray.push(val);
      $.get('/template/certification', { 'certification' : val }, function(data){
        $("div#certification-container").append(data);
        var last = $("div#certification-container")[0].children.length - 1;
        var child = $("div#certification-container")[0].children[last];
        
        $(child).click(function(){
          var index = $(child).index();
          var option = document.createElement("option");
          option.text = certificationArray[index];
          document.getElementById("user_certifications").add(option);
          sort_options("user_certifications");
          certificationArray.splice(index, 1);
          $(child).remove();
          
          
        });
      }, 'html');
    });
  });
  
   //CATEGORY-EQUIPMENT-CERTIFICATION STUFF (END)
  
  $("form.edit_admin_user").submit(function(e){
    e.preventDefault();
    
    var _this = $(this),
        uri   = _this[0].action,
        form  = new FormData(_this[0]);
  
    for (var i = 0; i < certificationArray.length; i++) {
      form.append("certifications[]", certificationArray[i]);
    };
    
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
      document.getElementById("status-save").innerHTML = "<img src='/assets/loader.gif' height='15px'> Saving project...";
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
  
  $('div#file-container').children().each(function(){
    var file_item = $(this);
    
    $("span.file-remove").click(function(e){
      var index = $(file_item).index();
      instructableFiles.splice(index, 1);
      document.getElementById("deletefiles").value = document.getElementById("deletefiles").value + e.target.id + ",";
      e.target.parentElement.remove();
    });

  });

}

function resetFormElement(e) {
  var el = $(e);
  el.wrap('<form>').closest('form').get(0).reset();
  el.unwrap();
}

function addFiles(fileArray, files, index){
  var file = files[index];
    if (true){
      fileArray.push(file);
      var reader = new FileReader();
      reader.readAsDataURL(file);
      reader.onload = function (e) {
        loadFile(file.name, fileArray);
        if( files.length !== ++index){
          addFiles(fileArray, files, index);
        }
      }
    }
};

function loadFile(filename, fileArray){
  var file_item = $('<div>').addClass('file-item');
  var close_button = $('<span>').addClass('file-remove');
  var span = $('<span>').textContent = filename;
  file_item.append(span);
  file_item.append(close_button);
  $.get('/template/file', { 'file' : filename }, function(file_item){
    $('div#file-container').append(file_item);
    var last = $("div#file-container")[0].children.length - 1;
    var child = $("div#file-container")[0].children[last];

    $(child.children[1]).click(function(){
      var index = $(child).index();
      fileArray.splice(index, 1);
      $(child).remove();
    });
  }, 'html');

  close_button.click(function(){
    var index = file_item.index();
    fileArray.splice(index, 1);
    file_item.remove();
  });
}

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

function sort_options (id) {
  $("#" + id).html($("#" + id + " option").sort(function (a, b) {
    if (!(a.text.includes("Select"))&&!(b.text.includes("Select"))) {
      return a.text.toLowerCase() == b.text.toLowerCase() ? 0 : a.text.toLowerCase() < b.text.toLowerCase() ? -1 : 1
    } 
  }));
  document.getElementById(id).selectedIndex = 0;
}