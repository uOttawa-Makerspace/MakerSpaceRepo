function selectAll(){
  $("input:checkbox").each(function(){
    $(this).attr('checked', true);
  });

  return false;
}
