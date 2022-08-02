[...document.getElementsByClassName("pp-status-button")].forEach(function (element) {
    if (element.innerHTML === "Revoked") {
        element.classList.add('btn-danger');
    } else if (element.innerHTML === "Awarded") {
        element.classList.add('btn-success');
    } else {
        element.classList.add('btn-warning');
    }
});
if (document.getElementById("badge_requirements")) {
    if (!document.getElementById("badge_requirements").tomselect){
        new TomSelect("#badge_requirements", {
            plugins: ['remove_button'],
            maxItems: null,
        });
    }
}
