$(document).on('turbolinks:load', function () {

    let page = location.pathname;
    let cookies = Cookies.get(page);
    if ((cookies != undefined) && (cookies != "")) {
        cookies = cookies.split(",");
        cookies.forEach(function (item) {
            document.getElementById(item).classList.toggle("show");
        });
    }

    $(".collapse").on('shown.bs.collapse', function(e){
        let page = location.pathname;
        storeid(page);
    });

    $(".collapse").on('hidden.bs.collapse', function(e){
        let page = location.pathname;
        storeid(page);
    });

});

window.storeid = function(page) {
    let className = document.getElementsByClassName('show');
    let classnameCount = className.length;
    console.log(classnameCount)
    let IdStore = new Array();
    for(let i = 0; i < classnameCount; i++){
        IdStore.push(className[i].id);
    }
    Cookies.set(page, IdStore.toString(), { expires: 1 });
};
