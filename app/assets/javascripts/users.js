
$(document).on('page:change', function(){ 

  directories();

  $("select").selectmenu({
    width: 422,
    position: { my : "left top+5", at: "left bottom" }
  });


});


function readURL(input) {
  if (input.files && input.files[0]) {
    var reader = new FileReader();

    reader.onload = function (e) {
      $('img.edit-avatar').attr('src', e.target.result);
    }
    reader.readAsDataURL(input.files[0]);
  }
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
