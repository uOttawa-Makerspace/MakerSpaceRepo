$(document).ready(function() {
  $("[id^=student]").hide();
  $(".class1").change(function() {

    $("[id^=student]").toggle(this.value == 'Grad');
  });
});

$(document).ready(function() {
  $("[id^=student]").hide();
  $(".class2").change(function() {
    $("[id^=student]").toggle(this.value == 'Undergrad');
  });
});
