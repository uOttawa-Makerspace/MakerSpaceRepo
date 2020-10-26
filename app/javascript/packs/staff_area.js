window.setSpace = function(){
    var space_id = document.getElementById("set_space_id").value;

    $.ajax({
        url: "/staff_dashboard/change_space",
        type: "PUT",
        data: {
            space_id: space_id,
            training: document.URL.includes("training_sessions")
        }
    })
}