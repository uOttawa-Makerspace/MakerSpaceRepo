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

// The direction each column of each table sorts in next: 1 going up, -1
// going down. A column sorts going up on its first click.
const nextDirections = new WeakMap();

function takeDirection(table, col) {
  const directions = nextDirections.get(table) || {};
  const direction = directions[col] || 1;
  directions[col] = -direction;
  nextDirections.set(table, directions);
  return direction;
}

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

// A column sorts as numbers when every cell that is not empty holds a number.
const NUMBER = /^-?\d+(\.\d+)?$/;

function isNumberColumn(keys) {
  const filled = keys.filter((key) => key !== "");
  return filled.length > 0 && filled.every((key) => NUMBER.test(key));
}

// Empty cells, and cells that are not dates in a date column, come before
// every value going up and after every value going down.
function valueOrLowest(value) {
  return Number.isNaN(value) ? -Infinity : value;
}

function comparableKeys(keys, isDateColumn) {
  if (isDateColumn) return keys.map((key) => valueOrLowest(Date.parse(key)));
  if (isNumberColumn(keys)) {
    return keys.map((key) => valueOrLowest(parseFloat(key)));
  }
  return keys.map((key) => key.toLowerCase());
}

function compareKeys(a, b) {
  if (a < b) return -1;
  return a > b ? 1 : 0;
}

// Rows with equal keys keep their order in both directions.
function sortRows(rows, col, isDateColumn, direction) {
  const keys = comparableKeys(
    rows.map((row) => sortKey(row, col).trim()),
    isDateColumn,
  );
  rows
    .map((row, i) => ({ row, key: keys[i] }))
    .sort((a, b) => direction * compareKeys(a.key, b.key))
    .forEach(({ row }) => row.parentNode.appendChild(row));
}

window.sortTable = function (table_name, col, isDateColumn = false) {
  const table = document.getElementsByClassName(table_name)[0];
  if (!table) return;

  const rows = [...table.getElementsByTagName("tr")].slice(1);
  sortRows(rows, col, isDateColumn, takeDirection(table, col));
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
