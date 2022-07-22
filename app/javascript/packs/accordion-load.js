/**
 * This class stores information about accordion states in local storage and sets states on page load. 
 */

document.addEventListener('turbolinks:load', () => {
    let storage = localStorage.getItem(location.pathname);
    if (storage) {
        storage = storage.split(",");
        storage.forEach(function (item) {
            let accordion_load_item = document.getElementById(item);
            if (accordion_load_item){accordion_load_item.classList.toggle("show");}
        });
    }
    const collapseElements = [...document.getElementsByClassName('collapse')];
    collapseElements.forEach((collapseElement) => {
        collapseElement.addEventListener('show.bs.collapse', (event) => {
            localStorage.setItem(location.pathname, localStorage.getItem(location.pathname) ? [...localStorage.getItem(location.pathname).split(","), event.target.id].toString() : [event.target.id]);
        });
        collapseElement.addEventListener('hide.bs.collapse', (event) => {
            localStorage.setItem(location.pathname, localStorage.getItem(location.pathname) ? localStorage.getItem(location.pathname).split(",").filter(el => el !== event.target.id).toString() : []);
        });
    });
});