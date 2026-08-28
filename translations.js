.pragma library

// Translation catalog. Keys are looked up by tr(key, lang); missing languages
// fall back to English, missing keys fall back to the key itself.
var strings = {
    "Quota": { fr: "Quota", es: "Cuota" },
    "no data": { fr: "aucune donnée", es: "sin datos" },
    "no quota reported": { fr: "aucun quota signalé", es: "sin cuota reportada" },
    "updated": { fr: "mis à jour", es: "actualizado" },
    "Refresh": { fr: "Actualiser", es: "Actualizar" },
    "resets in": { fr: "réinitialisation dans", es: "se reinicia en" },
    "resets soon": { fr: "réinitialisation imminente", es: "se reinicia pronto" },
    "just now": { fr: "à l'instant", es: "ahora mismo" },
    "disabled": { fr: "désactivé", es: "desactivado" },
    "unavailable": { fr: "indisponible", es: "no disponible" },
    "unsupported": { fr: "non pris en charge", es: "no compatible" },
    "last request": { fr: "dernière requête", es: "última solicitud" }
};

function tr(key, lang) {
    var entry = strings[key];
    if (!entry)
        return key;
    if (lang && entry[lang])
        return entry[lang];
    return key;
}
