console.log('Hello World');
if (document.getElementById("questions_trainings")) {
    if (!document.getElementById("questions_trainings").tomselect) {
        new TomSelect("#questions_trainings", {
            plugins: {
                "clear_button": { title: "Clear" }
            },
        });
    }
}
document.getElementById("pictureInput").addEventListener('change', function (event) {
    var files = event.target.files;
    var image = files;
    for (var i = 0; i < files.length; i++) {
        var reader = new FileReader();
        reader.onload = function (file) {
            var img = new Image();
            img.src = file.target.result;
            document.getElementById('image-target').insertBefore(img, null);
        }
        reader.readAsDataURL(image[i]);
    }
});