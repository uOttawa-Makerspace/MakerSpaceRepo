require("select2");

$(".user_select").select2({
    ajax: {
        url: "populate_users",
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
