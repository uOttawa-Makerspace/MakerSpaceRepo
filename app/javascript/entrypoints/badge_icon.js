const nameFr = document.getElementById("name_fr");

// Get the number of characters in the text element
const charCount = nameFr.getNumberOfChars();

if (charCount > 18) {
  nameFr.setAttribute("font-size", "0.4rem");
}
