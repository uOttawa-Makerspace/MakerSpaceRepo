document.getElementById("training_session_searchbar").addEventListener('keyup', debounce(function (e) {
    let xhr = new XMLHttpRequest();
    let formData = document.getElementById("training_session_searchbar").value;
    xhr.open('GET', '/admin/training_sessions?search=' + formData);
    xhr.send();
    xhr.onreadystatechange = function() {
        if (xhr.status == 200) {
           document.getElementsByClassName("table-training-sessions")[0].innerHTML = xhr.responseText;
        }
    }
},100));