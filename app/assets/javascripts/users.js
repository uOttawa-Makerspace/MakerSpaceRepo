function showField(){
	document.getElementById("hidden").style.display = 'block';
}
function hideField(){
	document.getElementById("hidden").style.display = 'none';
}

function showCreateButton(){
	var fake = document.getElementById("fake-signup-button");
	var real = document.getElementById("signup-button");
	if(fake.style.display != 'none'){
		fake.style.display = 'none';
		real.style.display = 'block';
	}else{
			fake.style.display = 'block';
			real.style.display = 'none';
	}
}

function showWaiver(toShow, toHide){
	document.getElementById(toShow).style.display = 'block';
	document.getElementById(toHide).style.display = 'none';
}


$(document).ready(function() {
  $(".programs").select2({});
});
