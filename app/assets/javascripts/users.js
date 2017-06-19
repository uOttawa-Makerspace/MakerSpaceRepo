$(document).ready(function() {
	$("#hidden").hide(); 
	$(".show_extra").change(function() { 
		if(this.value === "student") { 
			$("#hidden").show();
		} 
		else { 
			$("#hidden").hide(); 
		}
	});
});


$(document).ready(function() {
  $(".programs").select2({});
});