function validation(){
	var ret = true;
	var title = $("input#repository_title");
	$('span.form-error.repo-form').remove();
	var span = $('<span>').addClass('form-error repo-form');
	var regex = /^[-a-zA-Z\d\s]*$/;


	if( title.val().length === 0 ){
		span.text("Project title is required.");
		$('input#repository_title').before(span);
		ret = false;
	}

	if( !regex.test(title.val()) ){
		span.text("Project title may only contain letters and numbers.");
		$('input#repository_title').before(span);
		ret = false;
	}
  
  var oldPhotosLength = document.querySelectorAll("#image-container > div").length;

	span = $('<span>').addClass('form-error repo-form');

	if( (photoFiles.length === 0) && (oldPhotosLength == 0) ){
		span.text("At least one photo is required.");
		$('div.repo-image').before(span);
		ret = false;
	}

	span = $('<span>').addClass('form-error repo-form');
  
	if( categoryArray.length === 0 ){
		span.text("At least one category is required.");
		$('select#repository_categories').before(span);
		ret = false;
	}

	return ret;
}