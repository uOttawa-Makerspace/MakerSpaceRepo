$(document).ready(function() {
  $("[id^=student]").hide();
  $(".some-class").change(function() {
    $("[id^=student]").toggle(this.value == 'Student');
  });
});