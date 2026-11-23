.pragma library

var strings = {
    "Quota remaining": { fr: "Quota restant", es: "Cuota restante" },
    "Accounts": { fr: "Comptes", es: "Cuentas" },
    "Usage": { fr: "Utilisation", es: "Uso" },
    "All accounts": { fr: "Tous les comptes", es: "Todas las cuentas" },
    "Taskbar warnings": { fr: "Alertes dans la barre", es: "Avisos en la barra" },
    "on": { fr: "activées", es: "activados" },
    "off": { fr: "désactivées", es: "desactivados" },
    "Tokens per day": { fr: "Jetons par jour", es: "Tokens por día" },
    "Requests per day": { fr: "Requêtes par jour", es: "Solicitudes por día" },
    "Models": { fr: "Modèles", es: "Modelos" },
    "Today": { fr: "Aujourd'hui", es: "Hoy" },
    "7 days": { fr: "7 jours", es: "7 días" },
    "tokens": { fr: "jetons", es: "tokens" },
    "requests": { fr: "requêtes", es: "solicitudes" },
    "ok": { fr: "réussies", es: "correctas" },
    "failed": { fr: "échouées", es: "fallidas" },
    "other": { fr: "autre", es: "otros" },
    "over pace": { fr: "au-dessus du rythme", es: "sobre el ritmo" },
    "no data": { fr: "aucune donnée", es: "sin datos" },
    "no quota reported": { fr: "aucun quota signalé", es: "sin cuota reportada" },
    "no account is serving": { fr: "aucun compte en service", es: "ninguna cuenta en servicio" },
    "Loading…": { fr: "Chargement…", es: "Cargando…" },
    "Refreshing…": { fr: "Actualisation…", es: "Actualizando…" },
    "stale": { fr: "périmé", es: "desactualizado" },
    "data from": { fr: "données d'il y a", es: "datos de hace" },
    "Check the plugin settings or unlock your vault.": {
        fr: "Vérifiez les réglages du plugin ou déverrouillez votre coffre.",
        es: "Revisa los ajustes del plugin o desbloquea tu bóveda."
    },
    "The server sends a newer data format. Update this widget.": {
        fr: "Le serveur envoie un format de données plus récent. Mettez ce widget à jour.",
        es: "El servidor envía un formato de datos más reciente. Actualiza este widget."
    },
    "updated": { fr: "mis à jour", es: "actualizado" },
    "Refresh": { fr: "Actualiser", es: "Actualizar" },
    "resets in": { fr: "réinitialisation dans", es: "se reinicia en" },
    "resets soon": { fr: "réinitialisation imminente", es: "se reinicia pronto" },
    "just now": { fr: "à l'instant", es: "ahora mismo" },
    "shown above": { fr: "affiché ci-dessus", es: "mostrado arriba" },
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
