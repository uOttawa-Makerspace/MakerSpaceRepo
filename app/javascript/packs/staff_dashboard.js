var form = document.getElementById('sign_in_user_fastsearch');
form.onsubmit = function(){
    document.getElementById('sign_in_user_fastsearch_username').value = [document.getElementById('user_dashboard_select').value];
    form.submit();
};

var form2 = document.getElementById('search_user_fastsearch');
form2.onsubmit = function(){
    document.getElementById('search_user_fastsearch_username').value = document.getElementById('user_dashboard_select').value;
    form2.submit();
};

document.querySelector('.form-control-input-excel').addEventListener('change',function(e){
    var fileName = document.getElementById("excel-input").files[0].name;
    var nextSibling = e.target.nextElementSibling
    nextSibling.innerText = fileName
})


document.addEventListener("turbolinks:load", () => {
    setInterval(refreshCapacity, 60000)
});
refreshCapacity();
function refreshCapacity() {
    let url = "/staff_dashboard/refresh_capacity";
    fetch(url).then(response => response.text()).then(data => {document.getElementsByClassName('max_capacity_alert')[0].innerHTML = data.replace("\"","")});
}