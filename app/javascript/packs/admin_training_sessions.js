$('.training_session_searchbar').on('keyup', debounce(function (e) {
    $.ajax({
        url: '/admin/training_sessions',
        data: {search: $(this).serialize()},
        format: 'js'
    });
}, 100));