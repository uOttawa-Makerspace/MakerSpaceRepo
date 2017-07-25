$(document).ready(function() {
	$("#hidden").hide();
	$(".show_extra").change(function() {
		if(this.value === "private") {
			$("#hidden").show();
		}
		else {
			$("#hidden").hide();
		}
	});
});
