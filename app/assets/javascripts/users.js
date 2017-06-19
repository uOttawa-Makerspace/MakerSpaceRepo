$(document).ready(function() {
	$("#hidden").hide(); 
	$(".show_extra").change(function() { 
		if(this.value === "grad") { 
			$("#hidden").show();
		}
		else if(this.value === "undergrad") { 
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