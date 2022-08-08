function dragElement(elmnt) {
    var pos1, pos2, pos3, pos4 = 0;
    let header = elmnt.querySelector('.modal-header');
    header.onmousedown = dragMouseDown;
    function dragMouseDown(e) {
        e = e || window.event;
        pos3 = e.clientX;
        pos4 = e.clientY;
        document.onmouseup = closeDragElement;
        document.onmousemove = elementDrag;
    }

    function elementDrag(e) {


        elmnt.style.zIndex = ++curZ;
        e = e || window.event;
        e.preventDefault();
        pos1 = pos3 - e.clientX;
        pos2 = pos4 - e.clientY;
        pos3 = e.clientX;
        pos4 = e.clientY;
        if (pos3 - elmnt.offsetWidth / 2 > 0 && pos3 + elmnt.offsetWidth / 2 < window.innerWidth && pos4 > 0 && pos4 + elmnt.offsetHeight / 2 < window.innerHeight) {
            elmnt.style.top = (elmnt.offsetTop - pos2) + "px";
            elmnt.style.left = (elmnt.offsetLeft - pos1) + "px";
        }

    }

    function closeDragElement() {
        document.onmouseup = null;
        document.onmousemove = null;
    }
}
dragElement(document.getElementById("movableDialog"));