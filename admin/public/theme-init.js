// Applies the saved theme before first paint (external file: the panel's CSP forbids inline scripts).
try {
  var t = localStorage.getItem('zanjir-admin-theme')
  if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t
} catch (e) {}
