import TomSelect from 'tom-select';

new TomSelect('#user_dashboard_select', {
    valueField: 'username',
    labelField: 'name',
    searchField: 'name',
    load: function(query, callback) {
        fetch(`staff_dashboard/populate_users?search=${query}`)
            .then(response => response.json())
            .then(json => {
                callback(json.users);
            }).catch(()=>{
            callback();
        });
    },
    render: {
        option: function (item, escape) {
            return `<div>${item.name} (${item.username})</div>`;
        }
    }
});

let form = document.getElementById('sign_in_user_fastsearch');
form.onsubmit = function(){
    document.getElementById('sign_in_user_fastsearch_username').value = [document.getElementById('user_dashboard_select').value];
    form.submit();
};