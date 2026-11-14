window.findSession = function (table_class, id = "query") {
  var input, filter, table, tr, i, td, bingo, j, tdj;
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

function cellAt(row, col) {
  return row.getElementsByTagName("td")[col];
}

// sub_space_booking has date ranges, we can't parse the whole thing as a date
// So we specify the start date as the sort key.
// A row without a cell in the column sorts as an empty cell.
function sortKey(row, col) {
  const cell = cellAt(row, col);
  if (!cell) return "";
  return cell.dataset.sortAs || cell.innerText;
}

function inSortDirection(a, b) {
  return (sort_direction === 1 && a > b) || (sort_direction === 0 && a < b);
}

function outOfOrder(swapElStr, currElStr, isDateColumn) {
  if (isDateColumn) {
    return inSortDirection(Date.parse(swapElStr), Date.parse(currElStr));
  }
  return inSortDirection(swapElStr.toLowerCase(), currElStr.toLowerCase());
}

// The row, from row i down, that belongs at row i in the sort direction.
function rowForPosition(rows, i, col, isDateColumn) {
  let swapRow = rows[i];
  for (let j = i + 1; j < rows.length; j++) {
    if (
      outOfOrder(sortKey(swapRow, col), sortKey(rows[j], col), isDateColumn)
    ) {
      swapRow = rows[j];
    }
  }
  return swapRow;
}

function sortRows(rows, col, isDateColumn) {
  for (let i = 1; i < rows.length - 1; i++) {
    const swapRow = rowForPosition(rows, i, col, isDateColumn);
    rows[i].parentNode.insertBefore(swapRow, rows[i]);
  }
}

window.sortTable = function (table_name, col, isDateColumn = false) {
  const table = document.getElementsByClassName(table_name)[0];
  if (!table) return;

  sortRows(table.getElementsByTagName("tr"), col, isDateColumn);
  sort_direction = sort_direction === 1 ? 0 : 1;
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
