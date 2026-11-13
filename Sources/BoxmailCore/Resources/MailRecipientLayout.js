(() => {
  const root = document.getElementById('mail-content');
  if (!root) return;
  const labels = { '收件人': 'to', '抄送': 'cc', '密送': 'bcc', to: 'to', cc: 'cc', bcc: 'bcc' };
  const prefix = /^\s*(收件人|抄送|密送|to|cc|bcc)\s*[:：]\s*/i;
  const slots = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const textNodes = [];
  while (walker.nextNode()) textNodes.push(walker.currentNode);
  window.boxmailMailTextNodes = textNodes;
  const textOf = node => {
    const copy = node.cloneNode(true);
    for (const link of copy.querySelectorAll('a[href^="mailto:"]')) {
      let email = link.getAttribute('href').slice(7).split('?')[0];
      try { email = decodeURIComponent(email); } catch {}
      if (!link.textContent.includes(email)) link.appendChild(document.createTextNode(' <' + email + '>'));
    }
    return copy.textContent.trim();
  };
  const large = node => node.querySelectorAll('a[href^="mailto:"]').length > 8 || node.textContent.length > 600;
  const mount = (content, kind, stripLabel, insert) => {
    const slot = document.createElement('span');
    const id = slots.length;
    slot.className = 'boxmail-recipient-slot';
    slot.dataset.boxmailRecipientId = id;
    slot.setAttribute('aria-hidden', 'true');
    insert(slot);
    const value = () => stripLabel ? textOf(content).replace(prefix, '') : textOf(content);
    slots.push({ id, slot, kind, value, fields: [{ kind, value: value() }] });
  };
  const replace = (node, kind, stripLabel = false) => {
    if (node.tagName === 'LI') node.classList.add('boxmail-recipient-row');
    const content = document.createDocumentFragment();
    while (node.firstChild) content.appendChild(node.firstChild);
    mount(content, kind, stripLabel, slot => node.appendChild(slot));
  };
  for (const row of root.querySelectorAll('tr')) {
    const cells = Array.from(row.children).filter(cell => /^(TD|TH)$/.test(cell.tagName));
    if (cells.length < 2) continue;
    const kind = labels[cells[0].textContent.replace(/[\s:：]/g, '').toLowerCase()];
    if (!kind) continue;
    for (const cell of cells.slice(1)) {
      if (!large(cell)) continue;
      cells[0].classList.add('boxmail-recipient-label');
      replace(cell, kind);
    }
  }
  // Original/forward headers also occur as list items or paragraphs, not only tables.
  for (const node of root.querySelectorAll('li, p, div')) {
    if (node.querySelector('.boxmail-recipient-slot') || node.querySelector('table, ul, ol, p, div')) continue;
    if (Array.from(node.childNodes).some(child => child.nodeName === 'BR')) {
      const lines = [[]];
      for (const child of Array.from(node.childNodes)) {
        if (child.nodeName === 'BR') lines.push([]);
        else lines[lines.length - 1].push(child);
      }
      for (const line of lines) {
        if (!line.length) continue;
        const copy = document.createElement('span');
        for (const child of line) copy.appendChild(child.cloneNode(true));
        const match = copy.textContent.match(prefix);
        if (!match || !large(copy)) continue;
        const range = document.createRange();
        range.setStartBefore(line[0]); range.setEndAfter(line[line.length - 1]);
        const content = range.extractContents();
        mount(content, labels[match[1].toLowerCase()], true, slot => range.insertNode(slot));
      }
    } else {
      const match = node.textContent.match(prefix);
      if (match && large(node)) replace(node, labels[match[1].toLowerCase()], true);
    }
  }
  const report = () => window.webkit.messageHandlers.mailRecipientScrollRegions.postMessage(slots.map(({ id, slot, fields }) => {
    const rect = slot.getBoundingClientRect();
    return { id, fields, x: rect.x, y: rect.y, width: rect.width, height: rect.height };
  }));
  window.boxmailUpdateRecipients = () => {
    for (const item of slots) item.fields = [{ kind: item.kind, value: item.value() }];
    report();
  };
  for (const { slot } of slots) new ResizeObserver(report).observe(slot);
  new ResizeObserver(report).observe(root);
  report();
})();
