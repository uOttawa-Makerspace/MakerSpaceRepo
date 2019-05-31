function showHideDivs(){
    var passInfos = document.getElementsByClassName('pastInfo');
    var nextInfos = document.getElementsByClassName('nextInfo');
    for (var i = 0; i < passInfos.length; i++) {
        passInfos[i].style.display = "none";
    }
    for (var i = 0; i < nextInfos.length; i++) {
        nextInfos[i].style.display = "inline-block";
    }
}