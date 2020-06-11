$(document).ready(function() {
    $(".link_pp").select2({});
});

$(document).ready(function() {
    $("#user_select").on('change', function () {
        $.ajax({
            url: "populate_badge_list",
            type: "GET",
            data: {user_id: $(this).val()},
            success: function(data) {
                $("#badge_select").children().remove();
                let option;
                let dropdown = document.getElementById('badge_select');
                for (let i = 0; i < data['badges'].length; i++) {
                    option = document.createElement('option');
                    option.text = data['badges'][i].badge_template.badge_name;
                    option.value = data['badges'][i].acclaim_badge_id;
                    dropdown.add(option);
                }
            }
        })
    });
});

$(document).ready(function(){

    $(".grant_user_select").select2({
        ajax: {
            url: "populate_grant_users",
            type: "GET",
            dataType: 'json',
            delay: 250,
            data: function (params) {
                return {
                    search: params.term
                };
            },
            processResults: function (data) {
                return {
                    results: $.map(data.users, function (item) {
                        return {
                            text: item.name,
                            id: item.id
                        }
                    })
                };
            },
        },
        minimumInputLength: 3,
    });
});

$(document).ready(function(){

    $(".revoke_user_select").select2({
        ajax: {
            url: "populate_revoke_users",
            type: "GET",
            dataType: 'json',
            delay: 250,
            data: function (params) {
                return {
                    search: params.term
                };
            },
            processResults: function (data) {
                return {
                    results: $.map(data.users, function (item) {
                        return {
                            text: item.name,
                            id: item.id
                        }
                    })
                };
            },
        },
        minimumInputLength: 3,
    });
});

function debounce(func, wait, immediate) {
    var timeout;
    return function() {
        var context = this, args = arguments;
        var later = function() {
            timeout = null;
            if (!immediate) func.apply(context, args);
        };
        var callNow = immediate && !timeout;
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
        if (callNow) func.apply(context, args);
    };
};