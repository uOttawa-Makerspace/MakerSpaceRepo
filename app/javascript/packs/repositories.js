import TomSelect from 'tom-select';

window.showPass = function() {
	document.getElementById("password_repo_field").style.display = 'block'
};

window.hidePass = function() {
    document.getElementById("change_pass").style.display = 'none';
	document.getElementById("password_repo_field").style.display = 'none';
};
window.togglePass = function() {
    var x = document.getElementById("password_repo_field")
    if (x.style.display === 'none') {
        x.style.display = 'block'
    } else {
        x.style.display = 'none'
    }
}

document.addEventListener("turbolinks:load", function() {
    // $("#search_users_add").select2({});
    new TomSelect("#search_users",{
        searchField: ['name'],
        valueField: 'id',
        labelField: 'name',
        options: [],
        maxOptions: 5,
        searchOnKeyUp: true,
    })
    new TomSelect("#search_users_remove",{
        searchField: ['name'],
        valueField: 'id',
        labelField: 'name',
        options: [],
        maxOptions: 5,
        searchOnKeyUp: true,
    })
    // $("#search_users_remove").select2({});
});

