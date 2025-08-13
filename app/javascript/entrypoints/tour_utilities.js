// tour_utilities.js

export function getCookie(cname) {
  let name = cname + "=";
  let decodedCookie = decodeURIComponent(document.cookie);
  let ca = decodedCookie.split(";");
  for (let i = 0; i < ca.length; i++) {
    let c = ca[i];
    while (c.charAt(0) == " ") {
      c = c.substring(1);
    }
    if (c.indexOf(name) == 0) {
      return c.substring(name.length, c.length);
    }
  }
  return "";
}

export function setCookie(cname, cvalue) {
  document.cookie = cname + "=" + cvalue;
}

export function setCookieWithExp(cname, cvalue, exdays) {
  const d = new Date();
  d.setTime(d.getTime() + exdays * 24 * 60 * 60 * 1000);
  let expires = "expires=" + d.toUTCString();
  document.cookie = cname + "=" + cvalue + ";" + expires + ";path=/";
}

// Uses translations to find the according text given a key and a query parameter
export function translate(text, const_name) {
  if (window.location.search.includes("locale=en")) {
    return const_name.en[text];
  } else if (window.location.search.includes("locale=fr")) {
    return const_name.fr[text];
  } else {
    return const_name.en[text];
  }
}

// Toggles the locale of the entire site by changing the query parameter
export function toggleLocale(urlParams, curStep) {
  console.log("0");
  if (window.location.search.includes("locale=en")) {
    console.log("1");
    urlParams.set("locale", "fr");
    translations;
    urlParams.set("tour", curStep);
  } else if (window.location.search.includes("locale=fr")) {
    urlParams.set("locale", "en");
    console.log("2");
    urlParams.set("tour", curStep);
  } else {
    urlParams.set("locale", "fr");
    console.log("3");
    urlParams.set("tour", curStep);
  }
}

export function removeURLParameter(url, parameter) {
  //prefer to use l.search if you have a location/link object
  var urlparts = url.split("?");
  if (urlparts.length >= 2) {
    var prefix = encodeURIComponent(parameter) + "=";
    var pars = urlparts[1].split(/[&;]/g);

    //reverse iteration as may be destructive
    for (var i = pars.length; i-- > 0; ) {
      //idiom for string.startsWith
      if (pars[i].lastIndexOf(prefix, 0) !== -1) {
        pars.splice(i, 1);
      }
    }

    return urlparts[0] + (pars.length > 0 ? "?" + pars.join("&") : "");
  }
  return url;
}

export function setURL(url, param) {
  window.location.href = removeURLParameter(url, param);
}
