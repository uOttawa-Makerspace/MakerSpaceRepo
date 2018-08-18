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

function validation_proposal(){
    var ret = true;
    var title = $("input#project_proposal_title");
    var name = $("input#project_proposal_username")
    var email = $("input#project_proposal_email")
    var client = $("input#project_proposal_client")
    $('span.form-error.repo-form').remove();
    var span = $('<span>').addClass('form-error repo-form');
    var regex = /^[-a-zA-Z\d\s]*$/;


    if( title.val().length === 0 ){
        span.text("Project title is required.");
        $('input#project_proposal_title').before(span);
        ret = false;
    }

    if( !regex.test(title.val()) ){
        span.text("Project title may only contain letters and numbers.");
        $('input#project_proposal_title').before(span);
        ret = false;
    }

    if( name.val().length === 0 ){
        span.text("Your name is required");
        $('input#project_proposal_username').before(span);
        ret = false;
    }

    if( email.val().length === 0 ){
        span.text("Your email is required");
        $('input#project_proposal_email').before(span);
        ret = false;
    }

    if( client.val().length === 0 ){
        span.text("Client is required");
        $('input#project_proposal_client').before(span);
        ret = false;
    }

    return ret;
}