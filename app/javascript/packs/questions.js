$(document).on('turbolinks:load', function () {
    'use strict';
    window.addEventListener('load', function() {
        var forms = document.getElementsByClassName('needs-validation');
        var validation = Array.prototype.filter.call(forms, function(form) {
            form.addEventListener('submit', function(event) {
                if (form.checkValidity() === false) {
                    event.preventDefault();
                    event.stopPropagation();
                }
                form.classList.add('was-validated');
            }, false);
        });
    }, false);

    $('#pictureInput').on('change', function(event) {
        var files = event.target.files;
        var image = files;
        for(var i = 0; i < files.length; i++){
            var reader = new FileReader();
            reader.onload = function(file) {
                var img = new Image();
                img.src = file.target.result;
                document.getElementById('image-target').insertBefore(img, null);
            }
            reader.readAsDataURL(image[i]);
        }
        var editImage = document.getElementById("edit-image");
        if(editImage){
         editImage.style.display = "none";
        }
    });
});

$(document).on("turbolinks:load", function () {
    $("#questions_trainings").select2({
        allowClear: true,
        multiple: true
    });
});