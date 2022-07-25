import TomSelect from 'tom-select';
document.addEventListener("turbolinks:load", () => {
    let linkPP = document.querySelectorAll(".link-pp")
    linkPP.forEach(link => {
        new TomSelect(link, {});
    });
    if (document.getElementById("grant_user_select")) {
        new TomSelect("#grant_user_select", {
            searchField: ['name'],
            valueField: 'id',
            labelField: 'name',
            options: [],
            maxOptions: 5,
            searchPlaceholder: 'Choose User...',
            searchOnKeyUp: true,
            load: function (type, callback) {
                if (type.length < 2) { return; } else {
                    let url = "/badges/populate_grant_users?search=" + type;
                    fetch(url).then(response => response.json()).then(data => {
                        callback(data.users.map(user => { return { id: user.id, name: user.name } }));
                    });
                }
            },
            shouldLoad: function (type) {
                return type.length > 2;
            }
        });
    }
    if (document.getElementById("search_bar")) {
        document.getElementById("search_bar").addEventListener("keyup", function (event) {
            event.preventDefault();
            let query = document.getElementById("search_bar").value;
            if (query.length > 2) {
                let url = "/badges?search=" + query;
                fetch(url, {
                    method: "GET",
                    headers: {
                        'Accept': '*/*',
                    }
                }).then(response => response.text()).then(data => { document.getElementsByClassName("badge_list")[0].innerHTML = data; });
            }
        });
    }
    if (document.getElementById("revoke_user_select")) {
        new TomSelect("#revoke_user_select", {
            searchField: ['name'],
            valueField: 'id',
            labelField: 'name',
            options: [],
            maxOptions: 5,
            searchPlaceholder: 'Choose User...',
            searchOnKeyUp: true,
            load: function (type, callback) {
                if (type.length < 2) { return; } else {
                    let url = "/badges/populate_revoke_users?search=" + type;
                    fetch(url).then(response => response.json()).then(data => {
                        callback(data.users.map(user => { return { id: user.id, name: user.name } }));
                    });
                }
            },
            shouldLoad: function (type) {
                return type.length > 2;
            }
        });
    }
});