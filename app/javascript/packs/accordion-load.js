$(document).on('turbolinks:load', function () {

    let storage = localStorage.getItem(location.pathname);
    if ((storage != undefined) && (storage != "")) {
        storage = storage.split(",");
        storage.forEach(function (item) {
            let accordion_load_item = document.getElementById(item);
            if (accordion_load_item){accordion_load_item.classList.toggle("show");}
        });
    }

    $(".collapse").on('shown.bs.collapse', function(e){
        storeid(location.pathname);
    });

    $(".collapse").on('hidden.bs.collapse', function(e){
        storeid(location.pathname);
    });

});

window.storeid = function(page) {
    let className = document.getElementsByClassName('show');
    let classnameCount = className.length;
    let IdStore = new Array();
    for(let i = 0; i < classnameCount; i++){
        IdStore.push(className[i].id);
    }
    localStorage.setItem(page, IdStore.toString(), { expires: 1 });
};
