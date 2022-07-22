/**
 * This class stores information about accordion states in local storage and sets states on page load. 
 */

document.addEventListener('turbolinks:load', function() {
    let storage = localStorage.getItem(location.pathname);
    if ((storage != undefined) && (storage != "")) {
        storage = storage.split(",");
        storage.forEach(function (item) {
            let accordion_load_item = document.getElementById(item);
            if (accordion_load_item){accordion_load_item.classList.toggle("show");}
        });
    }
    let collapseElements = [...document.getElementsByClassName('collapse')];
    collapseElements.forEach(function (collapseElement) {
        collapseElement.addEventListener('show.bs.collapse', function () {
            storeid(location.pathname);
        });
        collapseElement.addEventListener('hide.bs.collapse', function () {
            storeid(location.pathname);
        });
    });
});

window.storeid = function(page) {
    let shownItems = document.getElementsByClassName('show');
    let IdStore = new Array();
    for(let i = 0; i < shownItems.length; i++){
        if (shownItems[i].id != ""){
            IdStore.push(shownItems[i].id);
        }
    }
    localStorage.setItem(page, IdStore.toString(), { expires: 1 });
};
