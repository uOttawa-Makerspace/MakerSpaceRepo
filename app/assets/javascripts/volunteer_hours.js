$(document).on('ready load', function () {
    'use strict';
    window.addEventListener('load', function() {
        var forms = document.getElementsByClassName('needs-validation');
        var validation = Array.prototype.filter.call(forms, function(form) {
            form.addEventListener('submit', function(event) {
                if (form.checkValidity() === false) {
                    event.preventDefault();
                    event.stopPropagation();
                } else{
                    var total_time_hidden = document.getElementById("total_time_hidden");
                    var hour = Number($("input#hours").val());
                    var minutes = Number($("input#minutes").val());
                    var total_time = hour + minutes/60.0;
                    total_time_hidden.value = total_time;
                }
                form.classList.add('was-validated');
            }, false);
        });
    }, false);
});

// $(function defineHoursMinutes(){
//     if($('body').is('.edit')){
//         var val_total_time_hidden = Number($("#total_time_hidden").val());
//         var val_hours = Math.floor(val_total_time_hidden);
//         var val_minutes = (val_total_time_hidden%1)*60;
//         var hour = $("input#hours");
//         var minutes = $("input#minutes");
//         hour.value = val_hours;
//         minutes.value = val_minutes;
//         console.log("hour");
//         console.log(val_hours);
//         console.log("minutes");
//         console.log(val_minutes);
//         console.log(hour);
//     }
// });