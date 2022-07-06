import TomSelect from 'tom-select';

document.addEventListener("turbolinks:load", () => {
    let linkPP = document.querySelectorAll(".link-pp")
    linkPP.forEach(link => {
        new TomSelect(link, {});
    });

    new TomSelect("#grant_user_select", {
        searchField: ['name'],
        valueField: 'id',
        labelField: 'name',
        options: [],
        maxOptions: 5,
        searchPlaceholder: 'Choose User...',
        searchOnKeyUp: true,
        load: function (type,callback) {
            if (type.length < 2) { return; } else {
                let url = "/badges/populate_grant_users?search=" + type;
                fetch(url).then(response => response.json()).then(data => {
                    callback(data.users.map(user => {return {id: user.id, name: user.name}}));
                });
            }
        },
        shouldLoad: function (type) {
            return type.length > 2;
        }
    });
    new TomSelect("#revoke_user_select", {
        searchField: ['name'],
        valueField: 'id',
        labelField: 'name',
        options: [],
        maxOptions: 5,
        searchPlaceholder: 'Choose User...',
        searchOnKeyUp: true,
        load: function (type,callback) {
            if (type.length < 2) { return; } else {
                let url = "/badges/populate_revoke_users?search=" + type;
                fetch(url).then(response => response.json()).then(data => {
                    callback(data.users.map(user => {return {id: user.id, name: user.name}}));
                });
            }
        },
        shouldLoad: function (type) {
            return type.length > 2;
        }
    });
});