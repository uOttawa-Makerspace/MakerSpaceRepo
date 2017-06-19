


$(document).ready(function() {
$(".show_extra").change(function() { if(this.value === "student") { $("#hidden").hide(); } else { $("#hidden").show(); }});
});




//   $("[id^=hidden]").hide();
//   $("div.radioselect").change(
//   	function() {
//     $("[id^=hidden]").toggle(this.value == "student");
//   	}
//   );
// }
// );

// $(document).ready(function() {
//   $("[id^=student]").hide();
//   $(".class2").change(function() {
//     $("[id^=student]").toggle(this.value == 'Undergrad');
//   });
// });



$(document).ready(function() {
  $(".states").select2({});
});