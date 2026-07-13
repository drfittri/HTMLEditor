const { ipcRenderer } = require("electron");
const fs = require("fs");

let pickerInstalled = false;
let pickerEnabled = true;
let selected = [];
let hover = null;

function installPicker() {
  if (pickerInstalled || !document.documentElement) return;
  pickerInstalled = true;

  const style = document.createElement("style");
  style.textContent = [
    ".__html_agent_hover{outline:1.5px solid rgba(34,197,94,.75)!important;outline-offset:2px!important;cursor:crosshair!important}",
    ".__html_agent_selected{outline:2px solid rgba(34,197,94,1)!important;outline-offset:3px!important;box-shadow:0 0 0 5px rgba(34,197,94,.14)!important}"
  ].join("\n");
  document.documentElement.appendChild(style);

  document.addEventListener("mouseover", (event) => {
    if (!pickerEnabled) return;
    if (hover && hover !== event.target) hover.classList.remove("__html_agent_hover");
    hover = event.target;
    if (hover && !isSelected(hover)) hover.classList.add("__html_agent_hover");
  }, true);

  document.addEventListener("mouseout", () => {
    if (hover && !isSelected(hover)) hover.classList.remove("__html_agent_hover");
  }, true);

  document.addEventListener("click", (event) => {
    if (!pickerEnabled) return;
    const element = event.target;
    if (!element || element === document.documentElement || element === document.body) return;

    event.preventDefault();
    event.stopPropagation();

    if (event.shiftKey) {
      const index = selected.indexOf(element);
      if (index >= 0) {
        selected.splice(index, 1);
        element.classList.remove("__html_agent_selected");
      } else {
        selected.push(element);
        element.classList.add("__html_agent_selected");
      }
    } else {
      clearSelected();
      selected = [element];
      element.classList.add("__html_agent_selected");
    }

    element.classList.remove("__html_agent_hover");
    postSelection();
  }, true);

  document.addEventListener("html-agent-set-picker-enabled", (event) => {
    pickerEnabled = Boolean(event.detail?.enabled);
    if (!pickerEnabled && hover) {
      hover.classList.remove("__html_agent_hover");
      hover = null;
    }
  });

  document.addEventListener("html-agent-clear-selection", () => {
    if (hover) {
      hover.classList.remove("__html_agent_hover");
      hover = null;
    }
    clearSelected();
    postSelection();
  });
}

function isSelected(element) {
  return selected.indexOf(element) !== -1;
}

function clearSelected() {
  selected.forEach((element) => element.classList.remove("__html_agent_selected"));
  selected = [];
}

function postSelection() {
  ipcRenderer.sendToHost("element-picked", selected.map(summarize));
}

function cssPath(element) {
  if (!element || element.nodeType !== 1) return "";
  const parts = [];
  let current = element;
  while (current && current.nodeType === 1 && current !== document.documentElement) {
    let part = current.tagName.toLowerCase();
    if (current.id) {
      part += `#${CSS.escape(current.id)}`;
      parts.unshift(part);
      break;
    }
    const classes = Array.from(current.classList || [])
      .filter((name) => !name.startsWith("__html_agent_"))
      .slice(0, 3);
    if (classes.length) part += `.${classes.map((name) => CSS.escape(name)).join(".")}`;
    let sibling = current;
    let nth = 1;
    while ((sibling = sibling.previousElementSibling)) {
      if (sibling.tagName === current.tagName) nth += 1;
    }
    part += `:nth-of-type(${nth})`;
    parts.unshift(part);
    current = current.parentElement;
  }
  return parts.join(" > ");
}

function summarize(element) {
  const rect = element.getBoundingClientRect();
  return {
    tag: element.tagName.toLowerCase(),
    id: element.id || "",
    className: Array.from(element.classList || [])
      .filter((name) => !name.startsWith("__html_agent_"))
      .join(" "),
    text: (element.innerText || element.textContent || "").replace(/\s+/g, " ").trim().slice(0, 500),
    selector: cssPath(element),
    outerHTML: element.outerHTML.slice(0, 1200),
    rect: {
      x: Math.round(rect.x),
      y: Math.round(rect.y),
      width: Math.round(rect.width),
      height: Math.round(rect.height)
    }
  };
}

// A page can build its own content at load, by script writing into the DOM. That content
// lives only in the live DOM -- the file holds the generator, not the result -- so markup
// in the file that the page regenerates is dead: editing it changes the file and nothing
// on screen. Diffing the file's own text (DOMParser runs no scripts) against what is
// actually rendered says whether the open page works that way, so the agent can be told to
// edit the data behind the content instead of the markup in front of it.
function reportGeneratedContent() {
  let source = "";
  try {
    source = fs.readFileSync(decodeURIComponent(new URL(location.href).pathname), "utf8");
  } catch (error) {
    return;
  }

  const overlay = (el) => el.tagName === "STYLE" || el.tagName === "SCRIPT";
  const kids = (el) => Array.from(el.children).filter((child) => !overlay(child));
  // Both sides are DOM-serialized, so attribute order and quoting normalize identically
  // and only real content differences survive.
  const sig = (el) => el.innerHTML.replace(/\s+/g, " ").trim();
  const same = (a, b) => a.tagName === b.tagName && (a.id || "") === (b.id || "");

  let generated = 0;
  const walk = (live, file) => {
    if (sig(live) === sig(file)) return;
    const lk = kids(live);
    const fk = kids(file);
    if (lk.length === fk.length && lk.every((el, i) => el.tagName === fk[i].tagName)) {
      if (lk.length) {
        lk.forEach((el, i) => walk(el, fk[i]));
        return;
      }
    }
    // A script that merely appended to a static container (a footer year, a back-to-top
    // button) is not a page that generates its content.
    let matched = 0;
    const extra = [];
    for (const el of lk) {
      if (matched < fk.length && same(el, fk[matched])) matched += 1;
      else extra.push(el);
    }
    const insertionOnly = matched === fk.length && fk.length > 0 && extra.length < lk.length;
    if (!insertionOnly) generated += 1;
  };

  try {
    const file = new DOMParser().parseFromString(source, "text/html");
    if (file.body && document.body) walk(document.body, file.body);
  } catch (error) {
    return;
  }
  ipcRenderer.sendToHost("generated-content", generated > 0);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", installPicker);
} else {
  installPicker();
}
// After load, so whatever the page builds for itself is already on screen.
if (document.readyState === "complete") reportGeneratedContent();
else window.addEventListener("load", reportGeneratedContent);
