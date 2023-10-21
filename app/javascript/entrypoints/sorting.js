window.findSession = function (table_class, id = "query") {
  var input, filter, table, tr, i;
  input = document.getElementById(id);
  filter = input.value.toUpperCase();
  table = document.getElementsByClassName(table_class)[0];
  tr = table.getElementsByTagName("tr");
  for (i = 1; i < tr.length; i++) {
    td = tr[i].getElementsByTagName("td");
    bingo = false;
    for (j = 0; j < td.length; j++) {
      tdj = td[j];
      if (tdj) {
        if (tdj.innerHTML.toUpperCase().indexOf(filter) > -1) {
          bingo = true;
          break;
        }
      }
    }
    if (bingo) {
      tr[i].style.display = "";
    } else {
      tr[i].style.display = "none";
    }
  }
};

var sort_direction = 1;
window.sortTable = function (table_name, col) {
  const table = document.getElementsByClassName(table_name)[0];
  var rows;
  var swapElement, currentElement;

  if (table) {
    rows = table.getElementsByTagName("tr");

    if (rows) {
      for (let i = 1; i < rows.length - 1; i++) {
        swapElement = rows[i].getElementsByTagName("td")[col];

        for (let j = i + 1; j < rows.length; j++) {
          currentElement = rows[j].getElementsByTagName("td")[col];

          if (
            (sort_direction === 1 &&
              swapElement.innerText.toLowerCase() >
                currentElement.innerText.toLowerCase()) ||
            (sort_direction === 0 &&
              swapElement.innerText.toLowerCase() <
                currentElement.innerText.toLowerCase())
          ) {
            swapElement = currentElement;
          }
        }

        rows[i].parentNode.insertBefore(swapElement.parentNode, rows[i]);
      }

      sort_direction = sort_direction === 1 ? 0 : 1;
    }
  }
};

var select_direction = 1;
window.selectAll = function (table_id) {
  if (select_direction == 1) {
    let boxes = document.getElementById(table_id).getElementsByTagName("input");
    for (let i = 0; i < boxes.length; i++) {
      boxes[i].checked = true;
    }
    select_direction = 0;
  } else {
    let boxes = document.getElementById(table_id).getElementsByTagName("input");
    for (let i = 0; i < boxes.length; i++) {
      boxes[i].checked = false;
    }
    select_direction = 1;
  }
  return false;
};
