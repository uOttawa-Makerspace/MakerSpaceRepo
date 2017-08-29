function showPass(){
	document.getElementById("password").style.display = 'block'
}

function hidePass(){
	$("#change_pass").hide();
	document.getElementById("password").style.display = 'none'
}
function togglePass() {
		var x = document.getElementById("password")
		if (x.style.display === 'none') {
			x.style.display = 'block'
		} else {
			x.style.display = 'none'
    }
}
