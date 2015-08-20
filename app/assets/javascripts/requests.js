$(document).on('page:change', function(){
 
  voting();
  
  $("form#comment").on("ajax:success", function(e, data, status, xhr) {

      params = {
        username: data.username,
        user_id: data.user_id,
        user_url: data.user_url,
        content: data.comment,
        rep: data.rep,
        comment_id: data.comment_id,
        created_at: data.created_at
      }

      $.get('/template/comment', params, function(data){
        var comment_count = $("span.comment-count").text();
        $("span.comment-count").text(parseInt(comment_count) + 1);
        $("div#comment-container").prepend(data);
        $("textarea#content").val("");

        voting();
        
      }, 'html');
  });


  $("a.like").on("ajax:success", function(e, data, status, xhr) {
    if(data.failed){ 
      $(this).effect( "pulsate", { times: 1 },  "fast" );
      return false; 
    }
    $("span.like-count").effect( "explode", 200, function(){
      $(this).text(data.like);
    });

    $("span.like-count").delay(200).effect( "fade", "slow");

    $("div.reputation").text(data.rep);
  });


});

function voting(){
  $("a.upvote, a.downvote").on("ajax:success", function(e, data, status, xhr) {
    var _this = $(this)[0];
    $(_this).siblings().css('color','#999');
    $(_this).siblings().each(function(){ 
      if( $(this)[0].localName === "div" ){ return; }
      this.href = this.origin + this.pathname + this.search.substring(0,11) +'&voted=' + data.voted;
    });
    _this.href = _this.origin + _this.pathname + _this.search.substring(0,11) +'&voted=' + data.voted; 
    $("div.upvote-" + data.comment_id ).text(data.upvote_count); 
    $(this).css('color', data.color); 
  });
}
