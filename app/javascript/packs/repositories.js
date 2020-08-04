function showPass(){
	document.getElementById("password_repo_field").style.display = 'block'
}

function hidePass(){
    $("#change_pass").hide();
	document.getElementById("password_repo_field").style.display = 'none'
}
function togglePass() {
    var x = document.getElementById("password_repo_field")
    if (x.style.display === 'none') {
        x.style.display = 'block'
    } else {
        x.style.display = 'none'
    }
}

$(document).on("turbolinks:load", function() {
    $("#search_users_add").select2({});
    $("#search_users_remove").select2({});
});
