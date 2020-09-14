window.setSpace = function(){
    var space_id = document.getElementById("set_space_id").value;
    console.log(space_id)
    $.ajax({
        url: "staff_dashboard/change_space",
        type: "PUT",
        data: {space_id: space_id}
    })
}