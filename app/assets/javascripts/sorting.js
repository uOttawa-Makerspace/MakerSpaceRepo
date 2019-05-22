function findSession(table_class, id = 'query') {
  var input, filter, table, tr, i;
  input = document.getElementById(id);
  filter = input.value.toUpperCase();
  table = document.getElementsByClassName(table_class)[0];
  tr = table.getElementsByTagName("tr");
  for (i = 1; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td");
    bingo = false;
    for(j = 0; j < td.length; j++){
      tdj = td[j];
      if (tdj) {
        if (tdj.innerHTML.toUpperCase().indexOf(filter) > -1) {
          bingo = true;
          break
        }
      }
    }
    if(bingo){
      tr[i].style.display = "";
    }else{
      tr[i].style.display = "none";
    }
    console.log(tr[i]);
  }
}

var sort_direction = 1;
function sortTable(table_class, col) {
  if(sort_direction === 1){
    var table, rows, switching, i, x, y, shouldSwitch;
    table = document.getElementsByClassName(table_class)[0];
    switching = true;
    while (switching) {
      switching = false;
      if(table){
        rows = table.getElementsByTagName("tr");
      }
      if (rows) {
        for (i = 1; i < (rows.length - 1); i++) {
          shouldSwitch = false;
          x = rows[i].getElementsByTagName("td")[col];
          y = rows[i + 1].getElementsByTagName("td")[col];
          if (x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
            shouldSwitch= true;
            break;
          }
        }
        if (shouldSwitch) {
          rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
          switching = true;
        }
      }
    }
    sort_direction = 0;
  }else{
    var table, rows, switching, i, x, y, shouldSwitch;
    table = document.getElementsByClassName(table_class)[0];
    switching = true;
    while (switching) {
      switching = false;
      if(table){
        rows = table.getElementsByTagName("tr");
      }
      if(rows){
        for (i = 1; i < (rows.length - 1); i++) {
          shouldSwitch = false;
          x = rows[i].getElementsByTagName("td")[col];
          y = rows[i + 1].getElementsByTagName("td")[col];
          if (x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
            shouldSwitch= true;
            break;
          }
        }
        if (shouldSwitch) {
          rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
          switching = true;
        }
      }
    }
    sort_direction = 1;
  }
}

var select_direction = 1;
function selectAll(table_id){
  if(select_direction == 1){
    boxes = document.getElementById(table_id).getElementsByTagName("input");
    for (i = 0; i < (boxes.length ); i++) {
      boxes[i].checked = true;
    }
    select_direction = 0;
  }else{
    boxes = document.getElementById(table_id).getElementsByTagName("input");
    for (i = 0; i < (boxes.length ); i++) {
      boxes[i].checked = false;
    }
    select_direction = 1;
  }
  return false;

}
