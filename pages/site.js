'use strict';
const copyButton = document.querySelector('#copy-brew');
const command = document.querySelector('#brew-command');
const copyStatus = document.querySelector('#copy-status');
copyButton.addEventListener('click', async () => {
  const text = command.textContent;
  // Copy within the user gesture first. Some embedded browsers leave the
  // asynchronous Clipboard API permission request unresolved indefinitely.
  const field = document.createElement('textarea');
  field.value = text;
  field.setAttribute('readonly', '');
  field.style.position = 'fixed';
  field.style.top = '-9999px';
  document.body.append(field);
  field.select();
  let copied = false;
  try { copied = document.execCommand('copy'); } catch (_) { copied = false; }
  field.remove();
  copyButton.focus();
  if (!copied && navigator.clipboard && window.isSecureContext) {
    try {
      copied = await Promise.race([
        navigator.clipboard.writeText(text).then(() => true),
        new Promise(resolve => setTimeout(() => resolve(false), 1200))
      ]);
    } catch (_) { copied = false; }
  }
  copyStatus.textContent = copied ? 'Homebrew command copied.' : 'Select the command above and copy it manually.';
  if (!copied) {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(command);
    selection.removeAllRanges();
    selection.addRange(range);
    command.focus();
  }
});
const dialog = document.querySelector('#image-dialog');
let imageTrigger;
if (typeof dialog.showModal === 'function') {
  document.querySelectorAll('[data-lightbox]').forEach(link => {
    link.addEventListener('click', event => {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      imageTrigger = link;
      const image = link.querySelector('img');
      document.querySelector('#dialog-image').src = link.href;
      document.querySelector('#dialog-image').alt = image.alt;
      document.querySelector('#dialog-caption').textContent = image.alt;
      document.querySelector('#dialog-original').href = link.href;
      dialog.showModal();
    });
  });
  dialog.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => { if (event.target === dialog) {
    const rect = dialog.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
  } });
  dialog.addEventListener('close', () => { if (imageTrigger) imageTrigger.focus(); });
}
