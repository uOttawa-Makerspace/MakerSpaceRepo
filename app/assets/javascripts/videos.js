function setProficientProject(){
    var proficient_project_id = document.getElementById("select_proficient_id").value;
    document.getElementById("proficient_project").innerHTML=("Proficient Project id chosen: " + proficient_project_id);
    check_proficient_project(proficient_project_id)
}

function s3_uploader(proficient_project_id) {
    $('#s3-uploader').S3Uploader(
        {
            additional_data: {proficient_project_id: proficient_project_id},
            remove_completed_progress_bar: false,
            progress_bar_target: $('#uploads_container'),
            before_add: function(file) {
                if (file.size > 8000485760) {
                    alert('Maximum file size is 8 GB');
                    return false;
                } else {
                    return true;
                }
            }
        }
    );

    // error handling
    $('#s3-uploader').bind('s3_upload_failed', function(e, content) {
        return alert(content.filename + ' failed to upload.');
    });
};

function check_proficient_project(proficient_project_id) {
    if(proficient_project_id.length === 0){
        document.getElementById("choose_video").classList.add('d-none');
    }else{
        document.getElementById("choose_video").classList.remove('d-none');
        s3_uploader(proficient_project_id)
    }
}