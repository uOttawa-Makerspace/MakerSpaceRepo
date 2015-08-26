$(document).on('page:change', function(){


  $('div.select-styled').change(function(){
    var _this = $(this);
    if(_this.text() == "Other"){
      $('span.other textarea').fadeIn(1);
    }else{
      $('span.other textarea').fadeOut(1);
    }
  });

  $("span.menu-button").hover(function(){
    $('ul.menu').fadeIn(100);
  }, function(){
    $('ul.menu').fadeOut(100);
  });
  
  $('div.repository-container').mouseenter(function(){
    var wrapper = $($(this)[0].firstElementChild);
    $(wrapper.children()[0]).fadeIn(100);
    $(wrapper.children()[1]).fadeIn(100);
  });

  $('div.repository-container').mouseleave(function(){
    var wrapper = $($(this)[0].firstElementChild);
    $(wrapper.children()[0]).fadeOut(100);
    $(wrapper.children()[1]).fadeOut(100);
  });

  $('a div.user-avatar').mouseenter(function(){
    $('div.edit-avatar').slideDown(200);
  });

  $('a div.user-avatar').mouseleave(function(){
    $('div.edit-avatar').fadeOut(200);
  });

  $('a.repository_report').click(function(){
    $('div.spinner').css('display', 'inline-block');
  });

  $("div#alert").fadeIn(500).delay(5000).fadeOut(300);
  $("div#notice").fadeIn(500).delay(5000).fadeOut(300);

   $("div#filter-header").click(function(){
    $('ul.filter').slideDown(100, function(){
      $(document).click(function(){
         $('ul.filter').slideUp(100);
         $(this).off('click');
      });
    });
  });

});