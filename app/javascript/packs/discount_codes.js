document.addEventListener("DOMContentLoaded", function(event) {
    let popovers = document.querySelectorAll("[data-bs-toggle=\"popover\"]")
    popovers.forEach(popover => {
        return new bootstrap.Popover(popover)
    });
});