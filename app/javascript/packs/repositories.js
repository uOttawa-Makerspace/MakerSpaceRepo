import TomSelect from 'tom-select';

window.showPass = function () {
    document.getElementById("password_repo_field").style.display = 'block'
};

window.hidePass = function () {
    if (document.getElementById("change_pass")) document.getElementById("change_pass").style.display = 'none';
    if (document.getElementById("password_repo_field")) document.getElementById("password_repo_field").style.display = 'none';
};
window.togglePass = function () {
    var x = document.getElementById("password_repo_field")
    if (x.style.display === 'none') {
        x.style.display = 'block'
    } else {
        x.style.display = 'none'
    }
}


document.addEventListener("DOMContentLoaded", function () {
    if (document.getElementById("search_users_add")) {
        new TomSelect("#search_users_add", {
            searchField: ['name'],
            valueField: 'id',
            labelField: 'name',
            maxOptions: 5,
            searchPlaceholder: 'Add Owner...',
            searchOnKeyUp: true,
            load: function (type, callback) {
                if (type.length < 2) { return; } else {
                    let url = "/repositories/populate_users?search=" + type;
                    fetch(url).then(response => response.json()).then(data => {
                        callback(data.users.map(user => { return { id: user.id, name: user.name } }));
                    });
                }
            },
            shouldLoad: function (type) {
                return type.length > 2;
            }
        })
    }
    if (document.getElementById("search_users_remove")) {
        new TomSelect("#search_users_remove", {
            searchField: ['name'],
            valueField: 'id',
            labelField: 'name',
            maxOptions: null,
            searchOnKeyUp: true,
        })
    }
    if (document.getElementById("search_project_proposals")) {
        new TomSelect("#search_project_proposals", {
            searchField: ['name'],
            valueField: 'id',
            labelField: 'name',
            maxOptions: null,
            searchOnKeyUp: true,
        })
    }
});

let equipmentArray = [];
let categoryArray = [];
document.addEventListener("turbolinks:load", function () {
    document.body.addEventListener("click", function (e) {
        if (e.target.classList.contains("equipment")) {
            let equipment = e.target.innerText;
            //remove equipment from array
            equipmentArray.splice(equipmentArray.indexOf(equipment), 1);
            let option = document.createElement("option");
            option.text = equipment;
            document.getElementById("repository_equipments").appendChild(option);
            e.target.remove();
        }else if (e.target.classList.contains("category")) {
            let category = e.target.innerText;
            //remove category from array
            categoryArray.splice(categoryArray.indexOf(category), 1);
            let option = document.createElement("option");
            option.text = category;
            document.getElementById("repository_categories").appendChild(option);
            e.target.remove();
        }
    });


    if (document.getElementById("equipment-container")) {
        [...document.getElementById("equipment-container").children].forEach(element => {
            console.log(element);
        });
    }
    if (document.getElementById("repository_equipments")) {
        document.getElementById("repository_equipments").addEventListener("change", function (el) {
            let val = el.target.options[el.target.selectedIndex].text;
            if ([...document.getElementById("equipment-container").children].length === 5) { return false; }
            for (let i = 0; i < equipmentArray.length; i++) {
                if (val == equipmentArray[i]) {
                    return false;
                }
            }
            el.target.remove(el.target.selectedIndex);
            el.target.selectedIndex = 0;
            el.preventDefault();
            equipmentArray.push(val);
            fetch("/template/equipment?equipment=" + val).then(response => response.text()).then(data => {
                let span = document.createElement("span");
                document.getElementById("equipment-container").append(span);
                span.outerHTML = data;
            });
        });
    }
    if (document.getElementById("repository_categories")) {
        document.getElementById("repository_categories").addEventListener("change", function (el) {
            let val = el.target.options[el.target.selectedIndex].text;
            if ([...document.getElementById("category-container").children].length === 5) { return false; }
            for (let i = 0; i < categoryArray.length; i++) {
                if (val == categoryArray[i]) {
                    return false;
                }
            }
            el.target.remove(el.target.selectedIndex);
            el.target.selectedIndex = 0;
            el.preventDefault();
            categoryArray.push(val);
            fetch("/template/category?category=" + val).then(response => response.text()).then(data => {
                let span = document.createElement("span");
                document.getElementById("category-container").append(span);
                span.outerHTML = data;
            });
        });
    }
    if (document.getElementById("category-container")) {
        [...document.getElementById("category-container").children].forEach(element => {
            [...document.getElementById("project_proposal_categories").options].forEach(option => {
                if (option.text == element.innerText) {
                    option.remove();
                }
            });
            categoryArray.push(element.innerText);
            element.addEventListener("click", function (e) {
                let option = document.createElement("option");
                option.text = e.target.innerText;
                document.getElementById("project_proposal_categories").appendChild(option);
                categoryArray.splice(categoryArray.indexOf(e.target.innerText), 1);
                e.target.remove();
            });
        });
    }
    //     $('div#category-container').children().each(function () {
//         let cat_item = $(this);
//         let x = document.querySelector("#repository_categories, #project_proposal_categories");
//         let id = x.id

//         for (let i = 0; i < x.options.length; i++) {
//             if (x.options[i].childNodes[0].nodeValue === cat_item[0].childNodes[0].nodeValue) {
//                 x.remove(i);
//             }
//         }
//         categoryArray.push(cat_item[0].innerText);

//         $(cat_item).click(function () {
//             let option = document.createElement("option");
//             option.text = cat_item[0].innerText;
//             x.add(option);
//             sort_options(id);
//             let index = $(cat_item).index();
//             categoryArray.splice(index, 1);
//             $(cat_item).remove();
//         });
});
