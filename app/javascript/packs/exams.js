

document.addEventListener('DOMContentLoaded', function() {
    window.addEventListener('popstate', function() {
        location.reload(true);
    });
});

