function showField(){
	document.getElementById("password").style.display = 'block'
}

function hideField(){
	$("#change_pass").hide();
	document.getElementById("password").style.display = 'none'
}
function toggleField() {
		var x = document.getElementById("password")
		if (x.style.display === 'none') {
			document.getElementById("password").style.display = 'block'
		} else {
			document.getElementById("password").style.display = 'none'
    }
}
