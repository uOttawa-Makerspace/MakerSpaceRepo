// ==UserScript==
// @name        Structure programs at uOttawa
// @namespace   Violentmonkey Scripts
// @match       https://catalogue.uottawa.ca/en/programs/*
// @grant       none
// @version     1.0
// @author      -
// @description 6/16/2024, 12:11:54 AM
// ==/UserScript==

// Find all levels
function get_filter_name(TagID) {
  Lists = document.getElementById(TagID).getElementsByTagName("li");
  return new Map(
    Array.from(Lists).map((e) => {
      let lbl = e.getElementsByTagName("label")[0];
      return [lbl.getAttribute("for"), lbl.textContent];
    })
  );
}

function get_programs_by_class(...filters) {
  return Array.from(document.getElementsByClassName(filters.join(" "))).map(
    (e) => {
      return e.textContent;
    }
  );
}

function classify_program(program) {
  switch (true) {
    case /Mech/.test(program):
      return "Mechanical";
    case /Civil/.test(program):
      return "Civil";
    case /Software|Elec|Comp|Cyber/.test(program):
      return "EECS";
    case /Chemical|Environ/.test(program):
      return "Chemical";
    default:
      return "SEDTI";
  }
}

LevelClasses = get_filter_name("cat21list");
FacultyClasses = get_filter_name("cat27list");
// Tweak faculty names
// Management -> Telfer School of Management
FacultyClasses = new Map(
  [...FacultyClasses].map(([k, v]) => {
    if (v.includes("Telfer")) {
      v = "Telfer School of Management";
    }
    return [k, v];
  })
);
console.log([...FacultyClasses]);

window.programs = {};
for ([lvl_filter, level] of LevelClasses) {
  programs[level] = {};
  for ([fac_filter, faculty] of FacultyClasses) {
    programs[level][faculty] = get_programs_by_class(lvl_filter, fac_filter);
  }
}
//console.log(JSON)

// We want CSV instead...
program_csv = [["program", "level", "faculty", "department"]];
for ([lvl_filter, level] of LevelClasses) {
  programs[level] = {};
  for ([fac_filter, faculty] of FacultyClasses) {
    for (program of get_programs_by_class(lvl_filter, fac_filter)) {
      program_csv.push([
        program.trim().replaceAll(",", ""),
        level,
        faculty,
        faculty == "Engineering"
          ? classify_program(program)
          : "Non-Engineering", // department
      ]);
    }
  }
}

// Trigger csv download
url =
  "data:text/csv;charset=UTF-8," +
  encodeURIComponent(program_csv.map((e) => e.join(",")).join("\n"));
window.open(url, "_blank").focus();

// IDEA: split engineering and non engineering
// BAD IDEA
/*
eng_programs = {} // Move engineering to a separate file
Object.keys(programs).forEach((level) => {
  //if(programs[level]['Engineering']) {
    eng_programs[level] = Object.groupBy(programs[level]['Engineering'], (prog) => classify_program(prog))
    delete programs[level]['Engineering']
  //}
})
*/

// Trigger json download
//url = "data:text/json;charset=UTF-8," + encodeURIComponent(JSON.stringify(programs))
//window.open(url, '_blank').focus();
//url = "data:text/json;charset=UTF-8," + encodeURIComponent(JSON.stringify(eng_programs))
//window.open(url, '_blank').focus();
