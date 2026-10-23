// Called only in WebKit's isolated client world. Mail scripts remain disabled.
const parse = source => new DOMParser().parseFromString(source, 'text/html').getElementById('mail-content');
const previous = parse(previousDocument), next = parse(nextDocument);
const signature = root => Array.from(root.querySelectorAll('*')).map(node =>
  [node.tagName, Array.from(node.attributes).map(a => [a.name, a.value]).sort()]);
const texts = root => {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  return nodes;
};
const root = document.getElementById('mail-content');
if (!root || !previous || !next || JSON.stringify(signature(previous)) !== JSON.stringify(signature(next))) return false;
const currentText = texts(root), nextText = texts(next);
if (currentText.length !== nextText.length) return false;
currentText.forEach((node, index) => {
  if (node.nodeValue !== nextText[index].nodeValue) node.nodeValue = nextText[index].nodeValue;
});
return true;
