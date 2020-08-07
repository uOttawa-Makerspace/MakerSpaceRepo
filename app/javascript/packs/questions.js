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
        var image = files[0]
        var reader = new FileReader();
        reader.onload = function(file) {
            var img = new Image();
            console.log(file);
            img.src = file.target.result;
            $('#image-target').html(img);
        }
        reader.readAsDataURL(image);
        console.log(files);

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