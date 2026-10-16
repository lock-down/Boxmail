(() => {
  const root = document.getElementById('mail-content');
  if (!root) return;
  for (const row of root.querySelectorAll('tr')) {
    const cells = Array.from(row.children).filter(cell => /^(TD|TH)$/.test(cell.tagName));
    if (cells.length < 2) continue;
    const label = cells[0].textContent.replace(/[\s:：]/g, '').toLowerCase();
    if (!['收件人', '抄送', '密送', 'to', 'cc', 'bcc'].includes(label)) continue;
    for (const cell of cells.slice(1)) {
      if (cell.querySelector('.boxmail-recipient-list')) continue;
      if (cell.querySelectorAll('a[href^="mailto:"]').length <= 8 && cell.textContent.length <= 600) continue;
      const list = document.createElement('div');
      list.className = 'boxmail-recipient-list';
      list.tabIndex = 0;
      list.setAttribute('role', 'region');
      list.setAttribute('aria-label', '引用邮件的收件人名单');
      while (cell.firstChild) list.appendChild(cell.firstChild);
      cell.appendChild(list);
    }
  }
  const lists = Array.from(root.querySelectorAll('.boxmail-recipient-list'));
  const report = () => window.webkit.messageHandlers.mailRecipientScrollRegions.postMessage(lists.map(list => {
    const rect = list.getBoundingClientRect();
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height,
      top: list.scrollTop, visible: list.clientHeight, total: list.scrollHeight };
  }));
  for (const list of lists) {
    list.addEventListener('scroll', report, { passive: true });
    new ResizeObserver(report).observe(list);
  }
  new ResizeObserver(report).observe(root);
  report();
})();
