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
window.sortTable = function (table_name, col, isDateColumn = false) {
  //console.log(`sortTable(${table_name}, ${col}, ${isDateColumn})`);
  const table = document.getElementsByClassName(table_name)[0];
  let rows;
  let swapElement, currentElement;

  if (table) {
    rows = table.getElementsByTagName("tr");

    if (rows) {
      for (let i = 1; i < rows.length - 1; i++) {
        swapElement = rows[i].getElementsByTagName("td")[col];

        for (let j = i + 1; j < rows.length; j++) {
          currentElement = rows[j].getElementsByTagName("td")[col];
          // sub_space_booking has date ranges, we can't parse the whole thing as a date
          // So we specify the start date as the sort key
          const swapElStr = swapElement.dataset.sortAs || swapElement.innerText;
          const currElStr =
            currentElement.dataset.sortAs || currentElement.innerText;

          if (
            !isDateColumn &&
            ((sort_direction === 1 &&
              swapElStr.toLowerCase() > currElStr.toLowerCase()) ||
              (sort_direction === 0 &&
                swapElStr.toLowerCase() < currElStr.toLowerCase()))
          ) {
            swapElement = currentElement;
          } else if (
            isDateColumn &&
            ((sort_direction === 1 &&
              Date.parse(swapElStr) > Date.parse(currElStr)) ||
              (sort_direction === 0 &&
                Date.parse(swapElStr) < Date.parse(currElStr)))
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
