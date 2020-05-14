$(function() {
    console.log("passing")
    $('#s3-uploader').S3Uploader(
        {
            remove_completed_progress_bar: false,
            progress_bar_target: $('#uploads_container'),
            before_add: function(file) {
                if (file.size > 2000485760) {
                    alert('Maximum file size is 2 GB');
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
});