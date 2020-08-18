require("select2");

$(".user_dashboard_select").select2({
    ajax: {
        url: "staff_dashboard/populate_users",
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
                        id: item.username
                    }
                })
            };
        },
    },
    minimumInputLength: 3,
});

var form = document.getElementById('sign_in_user_fastsearch');
form.onsubmit = function(){
    document.getElementById('sign_in_user_fastsearch_username').value = [document.getElementById('user_dashboard_select').value];
    form.submit();
};



