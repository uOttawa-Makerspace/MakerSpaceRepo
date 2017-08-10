$(document).ready(function() {
	$("#pass").hide();
	$(".show_extra").change(function() {
		if(this.value === "private") {
			$("#pass").show();
		}
		else {
			$("#pass").hide();
			$("#change_pass").hide();
		}
	});
});

 $(document).ready( function() {
	$("#change").on('change', function() {
	  $('#pass').toggle(this.checked);
	}).change();

});
