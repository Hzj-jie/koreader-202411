function send(action) {
  var xhtml = new XMLHttpRequest();
  xhtml.open("GET", "/koreader/event/" + action, false);
  xhtml.send();
  document.getElementById("result").innerHTML = xhtml.responseText;
}
