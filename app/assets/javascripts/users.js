function showField(){
	document.getElementById("hidden").style.display = 'block';
}
function hideField(){
	document.getElementById("hidden").style.display = 'none';
}

function showCreateButton(){
	if(document.getElementById("fake-signup-button").style.display != 'none'){
		document.getElementById("fake-signup-button").style.display = 'none';
		document.getElementById("signup-button").style.display = 'block';
	}else{
			document.getElementById("fake-signup-button").style.display = 'block';
			document.getElementById("signup-button").style.display = 'none';
		}
}

$(document).ready(function() {
  $(".programs").select2({});
});
