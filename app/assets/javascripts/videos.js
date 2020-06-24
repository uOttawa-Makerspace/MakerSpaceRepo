function setProficientProject(){
    var proficient_project_id = document.getElementById("select_proficient_id").value;
    document.getElementById("proficient_project").innerHTML=("Proficient Project id chosen: " + proficient_project_id);
    check_proficient_project(proficient_project_id)
}

function check_proficient_project(proficient_project_id) {
    if(proficient_project_id.length === 0){
        document.getElementById("choose_video").classList.add('d-none');
    }else{
        document.getElementById("choose_video").classList.remove('d-none');
    }
}