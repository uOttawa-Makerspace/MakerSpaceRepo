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
    var allAnswersSelected = clickedAnswer.parent().children("p.selected-answers");
    allAnswersSelected.removeClass('selected-answers');
    allAnswersSelected.addClass('answers');
    clickedAnswer.removeClass('answers');
    clickedAnswer.addClass('selected-answers');
}
