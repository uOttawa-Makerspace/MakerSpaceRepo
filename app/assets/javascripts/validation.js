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
  
	// if( categoryArray.length === 0 ){
	// 	span.text("At least one category is required.");
	// 	$('select#repository_categories').before(span);
	// 	ret = false;
	// }

	return ret;
}

function validation_proposal(){
    var title = $("input#project_proposal_title");
    var name = $("input#project_proposal_username");
    var email = $("input#project_proposal_email");
    var client = $("input#project_proposal_client");
    var client_background = $("input#project_proposal_client_background");
    var description = $("#trix_editor");
    $('span.form-error.repo-form').remove();
    var span = $('<span>').addClass('form-error repo-form');
    var regex = /^[-a-zA-Z\d\s]*$/;

    if( name.val().length === 0 ){
        span.text("Your name is required");
        $('input#project_proposal_username').before(span);
        reenable_button("project_proposal_username");
        console.log("PAssing")
        return false;
    }

    if( email.val().length === 0 ){
        span.text("Your email is required");
        $('input#project_proposal_email').before(span);
        reenable_button("project_proposal_email");
        return false;
    }

    if( client.val().length === 0 ){
        span.text("Client is required");
        $('input#project_proposal_client').before(span);
        reenable_button("project_proposal_client");
        return false;
    }


    if( title.val().length === 0 ){
        span.text("Project title is required.");
        $('input#project_proposal_title').before(span);
        reenable_button("project_proposal_title");
        return false;
    }

    if( !regex.test(title.val()) ){
        span.text("Project title may only contain letters and numbers.");
        $('input#project_proposal_title').before(span);
        reenable_button("project_proposal_title");
        return false;
    }

    if( client_background.val().length === 0 ){
        span.text("Client background is required.");
        $('input#project_proposal_client_background').before(span);
        reenable_button("project_proposal_client_background");
        return false;
    }

    if( description.val().length === 0 ){
        span.text("Description is required.");
        $('#trix_editor').before(span);
        reenable_button("trix_editor");
        return false;
    }
    return true
}


function reenable_button(element_id) {
    var elmnt = document.getElementById(element_id);
    elmnt.scrollIntoView(true);
    const scrolledY = window.scrollY;
    if (scrolledY) {
        window.scroll(0, scrolledY - 170);
    }
}