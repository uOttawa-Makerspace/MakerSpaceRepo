window.examResponse = function(exam_id, answer_id){
    $.ajax({
        url: "/exam_responses#create",
        type: "POST",
        dataType: 'json',
        data: {
            exam_id: exam_id,
            answer_id: answer_id
        }
    });
    changeAnswerClass()
}

function changeAnswerClass(){
    var clickedAnswer = $(event.target);
    if (typeof clickedAnswer.attr('class') !== 'undefined') {
        var allAnswersSelected = clickedAnswer.parent().children("div.selected-answers");
        allAnswersSelected.removeClass('selected-answers');
        allAnswersSelected.addClass('answers');
        clickedAnswer.removeClass('answers');
        clickedAnswer.addClass('selected-answers');
    } else {
        clickedAnswer = clickedAnswer.parent().parent();
        var allAnswersSelected = clickedAnswer.parent().children("div.selected-answers");
        allAnswersSelected.removeClass('selected-answers');
        allAnswersSelected.addClass('answers');
        clickedAnswer.removeClass('answers');
        clickedAnswer.addClass('selected-answers');
    }
}
