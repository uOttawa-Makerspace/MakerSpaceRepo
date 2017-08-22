var sort_direction = 1;

function findSession() {
  var input, filter, table, tr, i;
  input = document.getElementById("query");
  filter = input.value.toUpperCase();
  table = document.getElementById("sessions-table");
  tr = document.getElementsByTagName("tr");
  for (i = 0; i < tr.length; i++) {
    td0 = tr[i].getElementsByTagName("td")[0];
    td1 = tr[i].getElementsByTagName("td")[1];
    td2 = tr[i].getElementsByTagName("td")[2];
    td3 = tr[i].getElementsByTagName("td")[3];
    td4 = tr[i].getElementsByTagName("td")[4];
    td5 = tr[i].getElementsByTagName("td")[5];

    if (td1) {
      if (td0.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else if (td1.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      } else if (td2.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      }else if (td3.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      }else if (td4.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      }else if (td5.innerHTML.toUpperCase().indexOf(filter) > -1) {
        tr[i].style.display = "";
      }else {
        tr[i].style.display = "none";
      }
    }
  }
}


function sortTable(table_class, col) {
  if(sort_direction === 1){
    var table, rows, switching, i, x, y, shouldSwitch;
    table = document.getElementsByClassName(table_class)[0];
    switching = true;
    while (switching) {
      switching = false;
      rows = table.getElementsByTagName("tr");
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
    sort_direction = 0;
  }else{
    var table, rows, switching, i, x, y, shouldSwitch;
    table = document.getElementsByClassName(table_class)[0];
    switching = true;
    while (switching) {
      switching = false;
      rows = table.getElementsByTagName("tr");
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
    sort_direction = 1;
  }
}


function selectAll(table_id){
  boxes = document.getElementById(table_id).getElementsByTagName("input");
  for (i = 0; i < (boxes.length ); i++) {
    boxes[i].checked = true;
  }
  return false;
}
