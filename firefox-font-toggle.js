// Paste into Firefox's Browser Console (Cmd+Shift+J) to toggle ComicShanns live.
// Requires devtools.chrome.enabled=true (already set via user.js).
(() => {
  const sss = Cc["@mozilla.org/content/style-sheet-service;1"].getService(Ci.nsIStyleSheetService);
  const uri = Services.io.newURI("file:///Users/tylerearly/Library/Application%20Support/Firefox/Profiles/2l8opt4p.default-release/chrome/ui-font-off.css");
  const isOff = sss.sheetRegistered(uri, sss.AGENT_SHEET);
  if (isOff) {
    sss.unregisterSheet(uri, sss.AGENT_SHEET);
    Services.prefs.setIntPref("browser.display.use_document_fonts", 0);
    console.log("ComicShanns: ON (UI + all pages)");
  } else {
    sss.loadAndRegisterSheet(uri, sss.AGENT_SHEET);
    Services.prefs.setIntPref("browser.display.use_document_fonts", 1);
    console.log("ComicShanns: OFF (UI on system font, pages choose their own)");
  }
})();
