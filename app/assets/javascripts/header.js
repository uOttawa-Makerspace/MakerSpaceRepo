function toggleNav(){
    var toggleWidth = document.getElementById("mySidenav").style.width == "250px" ? "0" : "250px";
    $('#mySidenav').animate({ width: toggleWidth });
}

function closeNav() {
    document.getElementById("mySidenav").style.width = "0";
}
