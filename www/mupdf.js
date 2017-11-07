function noop() {
}

module.exports = {
    openPdf: function (url, title, options, dismissCallback, errorCallback) {
        cordova.exec(dismissCallback || noop, errorCallback || noop, "MuPdfPlugin", "openPdf", [url, title, options]);
    }
};
