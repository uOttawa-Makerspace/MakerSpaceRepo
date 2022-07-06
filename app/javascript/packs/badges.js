window.TomSelect = require('tom-select');

document.addEventListener("turbolinks:load", () => {
    let linkPP = document.querySelectorAll(".link-pp")
    linkPP.forEach(link => {
        new TomSelect(link, {});
    });
    let userSelect = document.getElementById("revoke_user_select");
    userSelect.addEventListener('change', function () {
        let userId = userSelect.value;
        let xhr = new XMLHttpRequest();
        xhr.open('GET', "/populate_badge_list?user_id" + userId, false);
        xhr.send();
        xhr.onreadystatechange = function () {
            if (xhr.status == 200) {
                let badgeSelect = document.getElementById("badge_select");
                while (badgeSelect.firstChild) {
                    badgeSelect.removeChild(badgeSelect.firstChild);
                }
                let badges = JSON.parse(xhr.responseText);
                badges.forEach(badge => {
                    let option = document.createElement("option");
                    option.text = badge.badge_template.badge_name
                    option.value = badge.acclaim_badge_id
                    badgeSelect.add(option);
                });
            }
        }
    });


    new TomSelect(document.getElementById("grant_user_select"), {
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
    new TomSelect(document.getElementById("revoke_user_select"), {
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