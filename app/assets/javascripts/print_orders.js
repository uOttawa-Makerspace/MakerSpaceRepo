function changeRadioOther() {
    var other = document.getElementById("other");
    other.checked = true;
    other.value = document.getElementById("inputother").value;
}
function changeRadioOther2() {
    var other2 = document.getElementById("other2");
    other2.checked = true;
    other2.value = document.getElementById("inputother2").value;
}
function change_price(radio) {
    if (radio.checked && radio.id === "other2") {
        document.getElementById("price1").innerHTML = "$0.56$/g";
        document.getElementById("price2").innerHTML = "$0.75$/g";
        document.getElementById("price3").innerHTML = "$0.94$/g";
    } else {
        document.getElementById("price1").innerHTML = "$0.30$/g";
        document.getElementById("price2").innerHTML = "$0.40$/g";
        document.getElementById("price3").innerHTML = "$0.50$/g";
    }
}
function change_color(radio) {
    if (radio.checked && radio.id === "Acrylic") {
        document.getElementById("color_form").style.display = 'block';
    } else {
        document.getElementById("color_form").style.display = 'none';
    }
}
function checkFile(yourForm){

    var file = yourForm.elements['print_order[final_file]'].value;

    if(file != ""){
        yourForm.submit();
    } else {
        if(confirm("Do you want to continue without adding a file ?")) {
            yourForm.submit();
        } else {
            return;
        }
    }
}