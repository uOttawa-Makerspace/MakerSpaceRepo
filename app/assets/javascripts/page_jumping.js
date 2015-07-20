$(document).on('page:change', function(){

  // PAGE JUMPING JAVASCRIPT
  $('a[href*=#]:not([href=#])').click(function() {
    if (location.pathname.replace(/^\//,'') == this.pathname.replace(/^\//,'') 
        && location.hostname == this.hostname) {
        var target = $(this.hash);
        target = target.length ? target : $('[name=' + this.hash.slice(1) +']');
            if (target.length) {
            if(target.selector == "#user-show-links" || 
               target.selector == "#repo-comments" ){ return; }
               $('html,body').animate({
                   scrollTop: target.offset().top
              }, 500);  
            return false;
        }
    }
  });
});