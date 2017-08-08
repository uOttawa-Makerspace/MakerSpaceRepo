$(document).ready(function() {
	$("#pass").hide();
	$(".show_extra").change(function() {
		if(this.value === "private") {
			$("#pass").show();
		}
		else {
			$("#pass").hide();
			$("#change").hide();
		}
	});
});


$(document).ready( function() {
	$("#pass").hide();
	// $("#repo_pass").hide();
	$("#change").on('change', function() {
	  $('#pass').toggle(this.checked);
	}).change();

});
