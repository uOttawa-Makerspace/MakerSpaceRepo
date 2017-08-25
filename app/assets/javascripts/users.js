function showField(){
	document.getElementById("hidden").style.display = 'block';
}
function hideField(){
	document.getElementById("hidden").style.display = 'none';
}
function showCreateButton(){
	document.getElementById("fake-signup-button").style.display = 'none';
	document.getElementById("signup-button").style.display = 'block';
}

$(document).ready(function() {
  $(".programs").select2({});
});
