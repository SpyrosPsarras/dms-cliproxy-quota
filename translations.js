.pragma library

// Translation catalog. Keys are looked up by tr(key, lang); missing languages
// fall back to English, missing keys fall back to the key itself.
var strings = {
    "Quota": { fr: "Quota", es: "Cuota" },
    "no data": { fr: "aucune donnée", es: "sin datos" }
};

function tr(key, lang) {
    var entry = strings[key];
    if (!entry)
        return key;
    if (lang && entry[lang])
        return entry[lang];
    return key;
}
